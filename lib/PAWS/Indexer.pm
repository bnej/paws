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

=head1 NAME

PAWS::Indexer - Index POD documents from files.

=for group paws_index

=cut

sub index_file {
    my $class = shift;
    my $e = shift; 
    my $filename = shift;
    
    my ($basename,$path,$suffix) = fileparse($filename,'.pm','.pod','.pl');
    
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
                          $atime,$mtime,$ctime,$blksize,$blocks)
                          = stat($filename);
    
    my $time_string = strftime('%Y-%m-%d', localtime($mtime));
    my $pa = Pod::Abstract->load_file($filename);

    my ($title, $shortdesc) = PAWS::extract_title($pa);

    return 0 unless $title;

    my @namespaces = split /::/,$title;
    my @head1 = map { $_->text } $pa->select('//head1@heading');
    my @head2 = map { $_->text } $pa->select('//head2@heading');

    $e->index(
        index => 'perldoc',
        type => 'module',
        id => $title,
        body => {
        	title => $title,
        	shortdesc => $shortdesc,
        	pod => $pa->pod,
        	head1 => [ @head1 ],
        	head2 => [ @head2 ],
        	links_to => [ map { $_->text } $class->links($pa) ],
        	date => $time_string,
        	namespaces => [ @namespaces ],
        	dims => $class->nav_groups($pa),
        	index_entries => [ $class->index_entries($pa) ],
        }
        );
    
    return (1)
}

sub links {
    my $class = shift;
    my $pa = shift;
    my %links = map { $_->link_info->{document} => $_ } 
                grep { $_->link_info->{document} } $pa->select('//:L|//@heading/:L|//@label/:L');

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

=head2 nav_groups

 my $nav_groups = $class->nav_groups($pa);

=for feature nav_selection

Find target dimensions for the current document - this will find
value/section for dd/feature C<=for> blocks, and just value lists for
C<group>.

=cut

sub nav_groups {
    my $class = shift;
    my $pa = shift;
    
    my @for_groups = $pa->select("//for[. =~ {^(group|feature|dd) }]");
    
    my %dims = ( 'group' => [ ], 'dd' => [ ] );
    foreach my $g (@for_groups) {
        my ($p_head) = $g->select('...[@heading](0)@heading');
        $g->body =~ m/(group|feature|dd)\s+(.*$)/;
        my ($type,$value) = ($1, $2);
        
        my @values = split /\s+/,$value;
        
        if($type eq 'feature' || $type eq 'dd') {
            $value = [ map { { 'value' => $_, 'in' => $p_head->text } } @values ];
        } else {
            $value = \@values;
        }
        
        push @{$dims{$type}}, @$value;
    }
    
    return \%dims;
}

sub index_entries {
    my $class = shift;
    my $pa = shift;
    
    my @index = $pa->select('//:X|//@heading/:X|//@label/:X');
    
    return map { $_->text } @index;
}

1;