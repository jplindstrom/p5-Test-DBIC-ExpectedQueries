package Test::DBIC::ExpectedQueries::Statistics;
use Moo;
extends "DBIx::Class::Storage::Statistics";

use Time::HiRes qw(time);
use Devel::StackTrace;

has queries => ( is => "lazy" );
sub _build_queries { [] }

has ignore_classes => ( is => "lazy" );
sub _build_ignore_classes { [] }

has start_time => ( is => "lazy" );
sub _build_start_time { 0 }



my $start_time = 0;
sub query_start {
    my $self = shift;
    my ($sql, @args) = @_;
    $self->start_time( time() );
}

sub query_end {
    my $self = shift;
    my ($sql, @args) = @_;

    my $start_time = $self->start_time;
    my $duration = $start_time
        ? time() - $start_time
        : 0;
    $self->start_time(0);

    chomp($sql);
    push(
        @{$self->queries},
        Test::DBIC::ExpectedQueries::Query->new({
            sql         => $sql,
            stack_trace => $self->_stack_trace(),
            duration    => $duration,
        }),
    );
}

sub _stack_trace {
    my $self = shift;

    my $trace = Devel::StackTrace->new(
        message      => "executed",
        ignore_class => @{$self->ignore_classes},
    );

    my $callers = $trace->as_string;
    chomp($callers);
    $callers =~ s/\n/ <-- /gsm;
    $callers =~ s/=?(HASH|ARRAY)\(0x\w+\)/<$1>/gsm;

    return $callers;
}

1;
