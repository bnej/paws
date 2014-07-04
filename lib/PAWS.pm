package PAWS;
use Dancer ':syntax';

use Pod::Abstract;
use File::Find;
use Pod::Abstract::Filter::summary;
use Pod::Abstract::Filter::overlay;
use Pod::Abstract::Filter::uncut;
use Pod::Abstract::Filter::sort;
use PodSummary;
use PAWS::Indexer;
use Pod::Abstract::BuildNode qw(node);

use Search::Elasticsearch;

our $VERSION = '0.1';

sub error_doc {
my $term = shift;
return <<EOF;

=head1 NAME

Error - Couldn't find a document called $term

=head2 DESCRIPTION

My not-so-clever search through your C<\@INC> path has failed, I guess that's no good.

EOF
}

my $elastic = undef;

sub elastic {
    my $self = shift
    return $elastic if defined $elastic;
    my $e = Search::Elasticsearch->new( nodes => [ 'localhost:9200' ] );
    $elastic = $e;
    
    return $e;
}

sub split_key($) {
    my $term = shift;
    return split ':',$term,2;
}

sub load_pa($) {
    my $term = shift;
    my ($doctype, $id) = split_key $term;
    
    my $e = elastic;
    
    my $results = $e->mget(
            index   => 'perldoc',
            type    => $doctype,
            body    => {
                docs => [
                    { _id => $id},
                ]
            }
        );
    my $doc = $results->{docs}[0];
    
    if($doc) {
        return Pod::Abstract->load_string($doc->{_source}{pod});
    } else {
        return Pod::Abstract->load_string(error_doc($term));
    }
}

sub extract_title($) {
    my $pa = shift;
    my ($name_para) = $pa->select("/head1[\@heading eq 'NAME']/:paragraph");
    if($name_para) {
        my $name = $name_para->text;

        my ($title, $sub) = split /\s+-+\s+/, $name;

        return $title, $sub;
    } else {
        return ("","")
    }
}

get '/' => sub {
    template 'index';
};

any '/load' => sub {
    my $key = params->{paws_key};
    my $view = params->{view};
    
    my $pa = load_pa $key;
    
    my ($name, $subtitle) = extract_title $pa;

    if($view eq 'summary') {
        my $summ = PodSummary->new->filter($pa);
        $_->detach foreach $summ->select('/head1[@heading eq \'NAME\']');
        $pa = $summ;
    } elsif($view eq 'uncut') {
        my $filter = Pod::Abstract::Filter::uncut->new;
        $pa = $filter->filter($pa);
    }
    if(params->{overlay}) {
        my ($overlay_list) = $pa->select("//begin[. =~ {^:overlay}](0)");
        if($overlay_list) {
            $pa = Pod::Abstract::Filter::overlay->new->filter($pa);
        }
    }
    if(params->{sort}) {
        $pa = Pod::Abstract::Filter::sort->new->filter($pa);
    }
    my ($doctype,$id) = split_key $key;
    $name = $id unless $name;
    
    template "display_module.tt", 
        { title => $name, sub => $subtitle, pa => $pa }, 
        {layout => undef};
};

any '/search' => sub {
    my $terms = params->{terms};
    my $view = params->{view};
    
    my $pa = load_pa $terms;
    
    my ($name, $subtitle) = extract_title $pa;

    if($view eq 'summary') {
        my $summ = PodSummary->new->filter($pa);
        $_->detach foreach $summ->select('/head1[@heading eq \'NAME\']');
        $pa = $summ;
    } elsif($view eq 'uncut') {
        my $filter = Pod::Abstract::Filter::uncut->new;
        $pa = $filter->filter($pa);
    }
    if(params->{overlay}) {
        my ($overlay_list) = $pa->select("//begin[. =~ {^:overlay}](0)");
        if($overlay_list) {
            $pa = Pod::Abstract::Filter::overlay->new->filter($pa);
        }
    }
    if(params->{sort}) {
        $pa = Pod::Abstract::Filter::sort->new->filter($pa);
    }
    $name = $terms unless $name;
    
    template "display_module.tt", 
        { title => $name, sub => $subtitle, pa => $pa }, 
        {layout => undef};
};

any '/menu' => sub {
    my $terms = params->{key};
    
    my $pa = load_pa $terms;

    my ($name, $subtitle) = extract_title $pa;

    my $summ = PodSummary->new->filter($pa);
    $_->detach foreach $summ->select('/head1[@heading eq \'NAME\']');
    
    template "display_menu.tt", 
        { title => $name, sub => $subtitle, pa => $summ }, 
        {layout => undef};
};

any '/complete' => sub {
    my $terms = params->{terms};
    
    my $e = elastic();
    my $results = $e->search(
        index => 'perldoc',
        type => 'module',
        _source => [ "title","shortdesc" ],
        body => {
            query => {
                multi_match => {
                    query => $terms,
                    fields => ["title^4", "shortdesc^2","head2^2", "pod"]
                }
            }
        }
        );
    
    my $out_mod = [ map { $_->{_source} } @{$results->{hits}{hits}} ];

    $results = $e->search(
        index => 'perldoc',
        type => 'function',
        _source => [ "title","shortdesc","parent_module" ],
        body => {
            query => {
                multi_match => {
                    query => $terms,
                    fields => ["title^4", "shortdesc^2","pod"]
                }
            }
        }
        );
    my $out_fn = [ map { $_->{_source} } @{$results->{hits}{hits}} ];
        
    my $out = {
        functions => $out_fn,
        modules => $out_mod,
    };
    
    template "autocomplete.tt",
        { results => $out },
        { layout => undef };
};

any '/inbound_links' => sub {
    my ($doctype,$original_doc) = split_key params->{key};
    
    my $e = elastic();
    my $results = $e->search(
        index => 'perldoc',
        type => 'module',
        _source => ['title'],
        body => {
            "query" => {
                "filtered" => {
                    "filter" => {
                        "term" => {
                	        "links_to" => [ $original_doc ]
            	        }
                	}
                }
            }
        }
        );
        
    my @out_links = map { node->link($_->{_source}{title}) } @{$results->{hits}{hits}};
    
    template "links.tt",
        {links => \@out_links},
        {layout => undef};
};

any '/links' => sub {
    my ($doctype,$module) = split_key params->{key};
    
    my $pa = load_pa params->{key};
    
    my @links = PAWS::Indexer->links($pa);
    
    template "links.tt", 
        { links => \@links }, 
        { layout => undef };
};

true;
