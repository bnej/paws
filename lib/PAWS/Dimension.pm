package PAWS::Dimension;
use strict;

use base qw(Pod::Abstract::Filter);
use Pod::Abstract::BuildNode qw(node nodes);
use PAWS;

sub filter {
    my $self = shift;
    my $pa = shift;
    
    my @grabs = $pa->select("//for[. =~ {^grab }]");

    my $e = PAWS->elastic;
    foreach my $g ( @grabs ) {
        my $v = $g->body;
        $v =~ s/^grab\s+//g;
        
        my ($dimension, $value) = split /\s+/, $v;
        
        my $docs = $self->find_dimension($e, $dimension, $value);
        
        my $over = node->over;
        my @contents = ( );
        foreach my $d (@$docs) {
            my $title = $d->{_source}{title};
            my $shortdesc = $d->{_source}{shortdesc};
            
            my @links = map { sprintf("L<< $title|$title/%s >>",$_->{in}) } grep {$_->{value} eq $value} @{$d->{_source}{dims}{$dimension}};
            my $links_string = join ", ", @links;
            $links_string = "- ". $links_string if $links_string;
            
my $item_pod = <<EOT;
=item L<< $title >>

$shortdesc $links_string

EOT
            push @contents, nodes->from_pod($item_pod);
        }
        $over->nest(@contents);
        
        $over->insert_after($g);
        $g->detach;
    }
    
    return $pa;
}

sub find_dimension {
    my ($self, $e, $dimension, $value) = @_;
    
    my $results = $e->search(
        index => 'perldoc',
        type => 'module',
        _source => ['title', 'dims', 'shortdesc' ],
        body => {
            "query" => {
                "filtered" => {
                    "filter" => {
                        "term" => {
                	        "dims.$dimension.value" => [ $value ]
            	        }
                	}
                }
            }
        }
        );
    return $results->{hits}{hits};
}

1;
