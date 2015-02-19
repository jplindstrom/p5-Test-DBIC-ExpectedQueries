=head1 NAME

Test::DBIC::ExpectedQueries - Test that no unexpected DBIx::Class queries are run


=head1 DESCRIPTION

Ensure that only the DBIx::Class SQL queries you expect are executed
while a particular piece of code under test is run.


=head2 Avoiding the n+1 problem

When following a relation off a row object it's easy to overlook the
fact that it's causing one query for each row in the resultset. This
can easily be solved by prefetching those relations, but you have to
know it happens first.

This module will help you with that, and to ensure you don't
accidentally start running many single row queries in the future.


=head1 SYNOPSIS

=head2 Simple case

    use Test::More;
    use Test::DBIC::ExpectedQueries;

    my $schema = ...;  # A DBIx::Class schema object

    # The return value of the subref is returned
    my $author_rows = expected_queries(
        # Collect stats for this schema
        $schema,
        # when running this code
        sub {
            $author_tree->create_authors_for_tabs($schema),
        },
        # and ensure these are the expected queries
        {
            # For the "tree_node" table
            tree_node => {
                update => ">= 1",  # Number of updates must be >= 1
                select => undef,   # Any number of selects are fine
            },
            # For the "author" table
            author => {
                update => 8,       # Number of updates must be exactly 8
            },
            user_session => {
                delete => "< 10",  # No more than 9 deletes allowed
            },
            # Any query on any other table will fail the test
        },
    );


=head2 Flexible case

The expected queries syntax is the same as above, but using the OO
interface allows you to collect stats for many separate
queries.

Useful for when you care about individual return values from methods
called, and when you don't know the expected number of queries until
after they have been run.

    use Test::More;
    use Test::DBIC::ExpectedQueries;

    my $queries = Test::DBIC::ExpectedQueries->new({ schema => $schema });
    my $author_rows = $queries->run(
        sub { $author_tree->create_authors_for_tabs($schema) },
    );

    $queries->run( sub { $author_tree->check_stuff() } );

    # ... test other things

    my $total_author_count = @{$author_rows} + 1; # or whatever
    $queries->test(
        {
            author     => {
                insert => $total_author_count,
                update => undef,
            },
            field      => { select => "<= 1" },
            tree_node  => { select => 2 },
        },
    );

=cut

package Test::DBIC::ExpectedQueries;

use Moo;
BEGIN {extends "Attribute::Exporter"};


use Test::More;
use Try::Tiny;
use Carp;
use DBIx::Class;

use Test::DBIC::ExpectedQueries::Query;



### Simple procedural interface

sub expected_queries : export_def {
    my ($schema, $subref, $expected) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $queries = Test::DBIC::ExpectedQueries->new({ schema => $schema });

    my $return_values;
    if (wantarray()) {
        $return_values = [ $queries->run($subref) ];
    }
    else {
        $return_values = [ scalar $queries->run($subref) ];
    }

    $queries->test($expected);

    return @$return_values if wantarray();
    return $return_values->[0];
}



### Full OO interface

has schema => (
    is       => "ro",
    required => 1,
);

has queries_sql => (
    is      => "rw",
    lazy    => 1,
    default => sub { [] },
    trigger => sub { shift->clear_queries },
    clearer => 1,
);

has queries => (
    is      => "rw",
    lazy    => 1,
    builder => "_build_queries",
    trigger => sub { shift->clear_table_operation_count },
    clearer => 1,
);
sub _build_queries {
    my $self = shift;
    return [
        map { Test::DBIC::ExpectedQueries::Query->new({ sql => $_ })}
        @{$self->queries_sql}
    ];
}

has table_operation_count => (
    is      => "lazy",
    clearer => 1,
);
sub _build_table_operation_count {
    my $self = shift;

    my $table_operation_count = {};
    for my $query (grep { $_->operation } @{$self->queries}) {
        $table_operation_count->{ $query->table }->{ $query->operation }++;
    }

    return $table_operation_count;
}



sub run {
    my $self = shift;
    my ($subref) = @_;

    my $storage = $self->schema->storage;

    my $previous_debug = $storage->debug();
    $storage->debug(1);

    my @queries_sql;
    my $previous_callback = $storage->debugcb();
    $storage->debugcb( sub {
        my ($op, $sql) = @_;
        push(@queries_sql, $sql);
    } );

    my $return_values;
    try {
        if (wantarray()) {
            $return_values = [ $subref->() ];
        }
        else {
            $return_values = [ scalar $subref->() ];
        }
    }
    catch { die($_) }
    finally {
        $storage->debugcb($previous_callback);
        $storage->debug($previous_debug);
    };

    $self->queries_sql([ @{$self->queries_sql}, @queries_sql ]);

    return @$return_values if wantarray();
    return $return_values->[0];
}

sub test {
    my $self = shift;
    my ($expected) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my $failure_message = $self->check_table_operation_counts($expected);
    if($failure_message) {
        fail("Expected queries for tables:\n\n$failure_message" . $self->unknown_warning);
        return 0;
    }

    pass("Expected queries for tables" . $self->unknown_warning);
    return 1;
}

sub check_table_operation_counts {
    my $self = shift;
    my ($expected_table_count, ) = @_;

    my $table_operation_count = $self->table_operation_count();

    my $expected_all_operation = $expected_table_count->{_all_} || {};
    my $table_test_result = {};
    for my $table (sort keys %{$table_operation_count}) {
        my $operation_count = $table_operation_count->{$table};
        for my $operation (sort keys %$operation_count) {
            my $actual_count = $operation_count->{$operation};
            my $expected_outcome = do {
                if ( exists $expected_table_count->{$table}->{$operation} ) {
                    $expected_table_count->{$table}->{$operation};
                }
                elsif (exists $expected_all_operation->{$operation}) {
                    $expected_all_operation->{$operation};
                }
                else { 0 }
            };
            defined($expected_outcome) or next;

            my $test_result = $self->test_count(
                $table,
                $operation,
                $expected_outcome,
                $actual_count,
            );
            $test_result and push(@{ $table_test_result->{$table} }, $test_result);
        }
    }

    ###JPL: also look at remaining in $expected, to make sure those
    ###queries are run

    if(scalar keys %$table_test_result) {
        my $message = "";
        for my $table (sort keys $table_test_result) {
            $message .= "* Table: $table\n";
            $message .= join("\n", @{$table_test_result->{$table}});
            $message .= "\nActually executed SQL queries on table '$table':\n";
            $message .= $self->sql_queries_for_table($table) . "\n\n";
        }
        return $message;
    }
    return "";
}

sub unknown_warning {
    my $self = shift;

    my @unknown_queries = $self->unknown_queries() or return "";

    return "\n\nWarning: unknown queries:\n" . join(
        "\n",
        map { $_->display_sql } @unknown_queries,
    ) . "\n";
}

sub unknown_queries {
    my $self = shift;
    return grep {  ! $_->operation } @{$self->queries};
}

sub sql_queries_for_table {
    my $self = shift;
    my ($table) = @_;
    return join(
        "\n",
        map  { $_->display_sql }
        grep { lc($_->table // "") eq lc($table // "") }
        @{$self->queries},
    );
}

sub test_count {
    my $self = shift;
    my ($table, $operation, $expected_outcome, $actual_count) = @_;

    my $expected_count;
    my $operator;
    if($expected_outcome =~ /^ \s* (\d+) /x) {
        $operator = "==";
        $expected_count = $1;
    }
    elsif($expected_outcome =~ /^ \s* (==|!=|>|>=|<|<=) \s* (\d+) /x) {
        $operator = $1;
        $expected_count = $2;
    }
    else {
        croak("expect_queries: invalid comparison ($expected_outcome)\n");
    }

    #                            actual,                expected
    my $comparison_perl = 'sub { $_[0] ' . $operator . ' $_[1] }';
    my $comparison = eval $comparison_perl; ## no critic
    $comparison->($actual_count, $expected_count) and return "";

    return "Expected '$expected_outcome' ${operation}s for table '$table', got '$actual_count'";
}

1;



__END__


=head1 AUTHOR

Johan Lindstrom, C<< <johanl [AT] cpan.org> >>



=head1 BUGS AND CAVEATS

=head2 BUG REPORTS

Please report any bugs or feature requests on GitHub:
L<https://github.com/jplindstrom/p5-Test-DBIC-ExpectedQueries/issues>.


=head2 KNOWN BUGS


=head2 CAVEATS


=head1 COPYRIGHT & LICENSE

Copyright 2015- Johan Lindstrom, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
