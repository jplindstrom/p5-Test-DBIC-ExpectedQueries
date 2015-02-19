
use strict;
use warnings;
use Test::More;

use lib "lib";
use Test::DBIC::ExpectedQueries;

my $queries = Test::DBIC::ExpectedQueries->new({
    schema => "don't run",
    queries_sql => [
        "UPDATE datum SET is_valid = ? WHERE ( id = ? )",
        "
sELECT *
from file",
    ]
});

is(scalar @{$queries->queries_sql}, 2, "Parsed out two queries");
is(scalar @{$queries->queries}, 2, "Parsed out two query objects");

my $query = $queries->queries->[0];
is($query->operation, "update", "Correct ->operation");
is($query->table, "datum", "Correct ->table");


$query = $queries->queries->[1];
is($query->operation, "select", "Correct ->operation");
is($query->table, "file", "Correct ->table");



done_testing();
