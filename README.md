p5-Test-DBIC-ExpectedQueries
============================

## NAME

Test::DBIC::ExpectedQueries - Test that no unexpected DBIx::Class
queries are run

## DESCRIPTION

Ensure that only the DBIx::Class SQL queries you expect are executed
while a particular piece of code under test is run.

### Avoiding the n+1 problem

When following a relation off a row object it's easy to overlook the
fact that it's causing one query for each row in the resultset. This can
easily be solved by prefetching those relations, but you have to know it
happens first.

This module will help you with that, and to ensure you don't
accidentally start running many single row queries in the future.


## Details

See [Test::DBIC::ExpectedQueries](ExpectedQueries/source/lib/Test/DBIC/) on metacpan.org

