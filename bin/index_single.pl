use Search::Elasticsearch;
use Data::Dumper;
use PAWS::Indexer;
use Pod::Abstract;
use POSIX qw(strftime);

use strict;
use warnings;

my $e = Search::Elasticsearch->new( nodes => [ 'localhost:9200' ] );
my $filename = $ARGV[0];

my $dc = PAWS::Indexer->index_file($e,$filename);

print "Indexed $dc from $filename\n";