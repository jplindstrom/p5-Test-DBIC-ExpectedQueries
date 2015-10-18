package Test::DBIC::ExpectedQueries::Statistics;
use base "DBIx::Class::Storage::Statistics";

use Time::HiRes qw(time);
use Devel::StackTrace;

my $start_time = 0;
sub query_start {
    my $self = shift;
    my ($sql, @args) = @_;
    $start_time = time();
}

sub query_end {
    my $self = shift;
    my ($sql, @args) = @_;

    my $duration = $start_time
        ? time() - $start_time
        : 0;

    my $queries = $self->{queries} ||= [];

    chomp($sql);
    push(
        @$queries,
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