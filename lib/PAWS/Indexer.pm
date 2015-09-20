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
        	nav_groups => [ $class->nav_groups($pa) ],
        	index_entries => [ $class->index_entries($pa) ],
        }
        );
    
    return (1)
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

sub nav_groups {
    my $class = shift;
    my $pa = shift;
    
    my @for_groups = $pa->select("//for[. =~ {^groups}]");
    
    my @groups = map { split /\s/, $_ } map { $_ =~ m/groups (.*$)/; $1 } @for_groups;
    
    return @groups;
}

sub index_entries {
    my $class = shift;
    my $pa = shift;
    
    my @index = $pa->select('//:X|//@heading/:X|//@label/:X');
    
    return map { $_->text } @index;
}

1;