package PAWS::PodSummary;
use strict;

use base qw(Pod::Abstract::Filter);
use Pod::Abstract::BuildNode qw(node);

our $VERSION = '0.20';

sub filter {
    my $self = shift;
    my $pa = shift;
    
    my @NAME = $pa->select("/head1[\@heading eq 'NAME']");
    
    my $summary = node->root;
    if(@NAME) {
        # Clone the original NAME section into the new document
        my @NEW_NAME = $_->duplicate foreach @NAME;
        $summary->nest(@NEW_NAME);
    }
    my $summ_block = node->head1('SUMMARY');
    $summary->nest($summ_block);
    
    $self->summarise_headings($pa,$summ_block);
    $summ_block->nest();
    $summ_block->coalesce_body(':text');
    
    return $summary;
}

sub summarise_headings {
    my $self = shift;
    my $pa = shift;
    my $summ_block = shift;
    my $depth = shift;
    $depth = 1 unless defined $depth;
    
    my @headings = $pa->select('/[@heading]');
    my @items = $pa->select('/over/item[@label =~ {[a-zA-Z]+}]'); # Labels that have strings
    
    unshift @headings, @items;
    return unless @headings;
    
    my $list = node->over;
    $summ_block->push($list);
    foreach my $head (@headings) {
        my ($hdg) = $head->select('@heading');
        if($head->type eq 'item') {
            ($hdg) = $head->select('@label');
        }
        my $hdg_text = $hdg->text;
        my $item = node->item($hdg_text);
        $item->param('original_serial',$head->serial); # Keep for contents linking
        if($hdg_text =~ m/^[0-9a-zA-Z_ ]+$/) {
            my ($synopsis) = $head->select("//:verbatim[. =~ {$hdg_text}](0)");
            if($synopsis) {
                $synopsis->detach;
                $item->nest($synopsis);
            }
        }
        $list->push($item);
            
        $self->summarise_headings($head, $item, $depth + 1);
    }
}

1;
