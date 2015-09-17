package PAWS::Indexer;

use Search::Elasticsearch;
use Data::Dumper;
use PAWS;
use Pod::Abstract;
use POSIX qw(strftime);
use Pod::Abstract::Node;
use Pod::Abstract::BuildNode qw(node);

use File::Spec;
use File::Basename;

use strict;
use warnings;

sub index_file {
    my $class = shift;
    my $e = shift; 
    my $filename = shift;
    
    my ($basename,$path,$suffix) = fileparse($filename,'.pm','.pod','.pl');
    
    my @dirs = grep { $_ && $_ !~ /^(lib|bin|doc)$/ } 
        File::Spec->splitdir( $path . $basename );

    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
                          $atime,$mtime,$ctime,$blksize,$blocks)
                          = stat($filename);
    
    my $time_string = strftime('%Y-%m-%d', localtime($mtime));
    my $pa = Pod::Abstract->load_file($filename);

    my ($title, $shortdesc) = PAWS::extract_title($pa);

    return 0 unless $title;

    my @func_indexed = $class->index_functions($pa, $time_string, $e);

    my @head2 = map { $_->text }  $pa->select('//head2@heading');

    $e->index(
        index => 'perldoc',
        type => 'module',
        id => $title,
        body => {
        	title => $title,
        	shortdesc => $shortdesc,
        	pod => $pa->pod,
        	head2 => [ @head2 ],
        	links_to => [ map { $_->text } $class->links($pa) ],
        	dirs => [ @dirs ],
        	date => $time_string,
        }
        );
    
    return (scalar(@func_indexed) + 1)
}

sub index_functions {
    my $class = shift;
    my $pa = shift;
    my $time_string = shift;
    my $e = shift;
    
    my ($title, $shortdesc) = PAWS::extract_title($pa);
    my @func_h2 = $pa->select('/head1[@heading =~ {METHODS|FUNCTIONS}]/head2');

    foreach my $f (@func_h2) {
        my $fname = $f->param('heading')->text;
        my $short = '';
        if($fname =~ m/^[0-9a-zA-Z_ ]+$/) {
            my ($in_cut) = $f->select("//#cut[. =~ {$fname}](0)");
            my ($synopsis) = $f->select("//:verbatim[. =~ {$fname}](0)");
            if($synopsis) {
                $short = $synopsis->pod;
            }
        
            # If it doesn't appear in the cut nodes below, and doesn't have a
            # synopsis, skip it.
            next unless $in_cut || $synopsis;
        }

        $e->index(
            index => 'perldoc',
            type => 'function',
            id => $title . '::' . $fname,
            body => {
                pod => $f->pod,
                title => $fname,
                parent_module => $title,
                shortdesc => $short,
            	date => $time_string,
        	},
            );
    }
    
    return @func_h2;
}

sub links {
    my $class = shift;
    my $pa = shift;
    my %links = map { $_->link_info->{document} => $_ } 
                grep { $_->link_info->{document} } $pa->select("//:L");

    # Find the "SEE ALSO" section and extract all the module names
    my ($see_also) = $pa->select("/head1[\@heading eq 'SEE ALSO']");
    if($see_also) {
        foreach my $text ($see_also->select("//:text")) {
            my $str = $text->body;
            my @matches = $str =~ m/(\w+\:\:[\w\:]+)/g;
            foreach my $l (@matches) {
                my $link = node->link($l);
                $links{$l} = $link;
            }
        }
    }
    my @links = map { $links{$_} } sort keys %links;
    return @links;
}

1;