package PAWS;
use Dancer ':syntax';

use Pod::Abstract;
use File::Find;
use Pod::Abstract::Filter::summary;
use Pod::Abstract::Filter::overlay;
use Pod::Abstract::Filter::uncut;
use Pod::Abstract::Filter::sort;
use POSIX qw(strftime);
use PAWS::PodSummary;
use PAWS::Indexer;
use PAWS::Dimension;
use Pod::Abstract::BuildNode qw(node);
use Digest::MD5 qw(md5_hex);
use Search::Elasticsearch;

use Data::Dumper;

our $VERSION = '0.1';

sub error_doc {
my $term = shift;
return <<EOF;

=head1 NAME

Error 404 - Couldn't find a document called $term

=head1 DESCRIPTION

I don't have an indexed document for $term.

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

sub load_pa($$) {
    my $doctype = shift;
    my $id = shift;
    
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
    
    if($doc->{found}) {
        return Pod::Abstract->load_string($doc->{_source}{pod});
    } else {
        return Pod::Abstract->load_string(error_doc($id));
    }
}

sub load_annotation {
    my $module = shift;
    my $key = shift;
    
    my $digest_key = md5_hex($module . '|' . $key);
    my $e = elastic;
    my $results = $e->mget(
            index   => 'perldoc',
            type    => 'annotation',
            body    => {
                docs => [
                    { _id => $digest_key},
                ]
            }
        );
    my $doc = $results->{docs}[0];
    
    if($doc->{_source}) {
        return $doc->{_source}{pod};
    } else {
        return '';
    }
}

sub load_annotations {
    my $module = shift;
    
    my $e = elastic();
    my $results = $e->search(
        index => 'perldoc',
        type => 'annotation',
        _source => ['date','module','doc_path','pod'],
        body => {
            "query" => {
                "filtered" => {
                    "filter" => {
                        "term" => {
                	        "module" => $module
            	        }
                	}
                }
            }
        }
        );
    my %anno = map { 
        $_->{_source}{doc_path} => Pod::Abstract->load_string("=pod\n\n".$_->{_source}{pod})
    } grep { $_->{_source}{pod} !~ m/^\s*$/ } @{$results->{hits}{hits}};
    
    return \%anno
}

sub merge_annotations {
    my $pod = shift; my $anno = shift;
    
    for my $node ($pod->select("//[\@heading | \@label]")) {
        my $path = $node->path_to;
        if(my $ap = $anno->{$path}) {
            $ap->type('annotation'); # Force a type change - special case.
            $node->unshift($ap);
        }
    }
}

sub extract_title($) {
    my $pa = shift;
    my ($name_para) = $pa->select("/head1[\@heading =~ {^NAME}]/:paragraph");
    my ($title_exact) = $pa->select("//for[. =~ {^title }]");
    
    if($title_exact) {
        my $body = $title_exact->body;
        $body =~ s/^title //;
        my ($title, $sub) = split /\s+-+\s+/, $body;
        
        return ($title, $sub) if $sub;
        return $body;
    }elsif($name_para) {
        my $name = $name_para->text;

        my ($title, $sub) = split /\s+-+\s+/, $name;

        return $title, $sub;
    } else {
        my ($head1) = $pa->select('/head1(0)@heading');
        if($head1) {
            if(length($head1->text) > 30) {
                warn "This heading ",$head1->text," seems too long to index";
                return ('','');
            }
            return ($head1->text, '');
        } else {
            return ("","")
        }
    }
}

get '/' => sub {
    set layout => 'main.tt';
    
    my $key = 'index';
    my $view = 'normal';

    my $r = load_key_view($key, $view);
    
    template 'index', $r;
};

get qr{/([^\_][^/]*)((?:/(?:[^/\@]*))?)((?:/\@(?:[^/]*))?)} => sub {
    set layout => 'main.tt';
    my ($key, $view, $target) = splat;
    if($view) {
        $view =~ s/^\///;
    } else {
        $view = 'normal';
    }
    
    if($target) {
        $target =~ s/^\/\@//;
    }
    
    my $r = load_key_view($key, $view, $target);
    
    template 'index', $r;
};

get '/_index' => sub {
    
};

post '/_edit_annotation' => sub {
    my $module = params->{module};
    my $node_path = params->{node_path};
    
    my $anno = load_annotation($module,$node_path);
    
    template "editor",
        { module => $module, node_path => $node_path, annotation => $anno },
        { layout => undef };
};

post "/_save_annotation" => sub {
    my $module = params->{module};
    my $node_path = params->{node_path};

    my $annotation = params->{annotation};
    $annotation =~ s/\r\n/\n/g;
    my $digest_key = md5_hex($module . '|' . $node_path);
    my $time_string = strftime('%Y-%m-%d', localtime(time));
    
    my $e = elastic;
    $e->index(
        index => 'perldoc',
        type => 'annotation',
        id => $digest_key,
        body => {
            pod => $annotation,
            module => $module,
            doc_path => $node_path,
        	date => $time_string,
        	updated_by => 'web',
    	},
        );
    
    return { saved => 'yes' };
};

any '/_load' => sub {
    header('Cache-Control' =>  'no-store, no-cache, must-revalidate');
    my $key = params->{paws_key};
    my $view = params->{view};
    my $section = params->{section};

    return load_key_view($key, $view, $section);
};

sub load_key_view {
    my $key = shift;
    my $view = shift;
    my $section = shift;
    
    my $pa = load_pa 'module',$key;
    
    my ($name, $subtitle) = extract_title $pa;

    if($view eq 'summary') {
        my $summ = PAWS::PodSummary->new->filter($pa);
        $_->detach foreach $summ->select('/head1[@heading eq \'NAME\']');
        $pa = $summ;
    } elsif($view eq 'uncut') {
        my $filter = Pod::Abstract::Filter::uncut->new;
        $pa = $filter->filter($pa);
    }
    
    my $dim_grab = PAWS::Dimension->new;
    $pa = $dim_grab->filter($pa);
    
    if(params->{overlay}) {
        my ($overlay_list) = $pa->select("//begin[. =~ {^:overlay}](0)");
        if($overlay_list) {
            $pa = Pod::Abstract::Filter::overlay->new->filter($pa);
        }
    }
    if(params->{sort}) {
        $pa = Pod::Abstract::Filter::sort->new->filter($pa);
    }
    $name = $key unless $name;

    my $anno = load_annotations($name);
    merge_annotations($pa, $anno);

    my $content = template "display_module.tt", 
        { title => $name, sub => $subtitle, pa => $pa }, 
        {layout => undef};
    
    my $summ = PAWS::PodSummary->new->filter($pa);
    $_->detach foreach $summ->select('/head1[@heading eq \'NAME\']');
    
    my $menu = template "display_menu.tt", 
            { title => $name, sub => $subtitle, pa => $summ }, 
            {layout => undef};

    my @links = PAWS::Indexer->links($pa);

    my $links = template "links.tt", 
        { links => \@links }, 
        { layout => undef };
    
    # Find a link target, if provided:
    my $section_target = undef;
    if($section) {
        my @headings = $pa->select('//[@heading|@label]');
        foreach my $head(@headings) {
            my ($hdg) = $head->param('heading') || $head->param('label');
            my $hdg_text = $hdg->text;
            
            if($hdg_text eq $section) {
                $section_target = $head->serial;
                last;
            }
        }
        
        if(!$section_target) {
            my @ix = $pa->select('//:X|//@heading/:X|//@label/:X');
            foreach my $ixe (@ix) {
                my $it = $ixe->text;

                if($it eq $section) {
                    $section_target = $ixe->serial;
                    last;
                    
                }
            }
        }
    }    
    
    return {
        active_document => $key,
        content => $content,
        menu => $menu,
        links => $links,
        inbound_links => inbound_links($key),
        section_name => $section,
        section_target => $section_target,
    };
}

any '/_complete' => sub {
    my $terms = params->{terms};
    my $filter_ns = params->{filter_namespaces};
    
    my $filter = {
        };
    my %selected = ( );
    if($filter_ns) {
        my @ns = split /\s/, $filter_ns;
        $filter->{term} = {
            namespaces => [ @ns ],
            execution => "and"
        };
        $selected{$_} = 1 foreach @ns;
    }
    
    my %query = ( 
        query => {
            filtered => {
                filter => $filter
            }
        }
        );
        
    if($terms) {
        %query = ( query => {
            filtered => {
                query => {
                    multi_match => {
                        query => $terms,
                        fields => ["title^4","index_entries^5","shortdesc^2","head2^2", "module", "pod"]
                    }
                },
                filter => $filter
            }
        },
        "highlight"=> {
          "fields"=> {
            "title"=> {},
            "index_entries"=> {},
            "shortdesc"=> {},
            "head2"=> {}
          }
        },
        )
    }
    
    my $e = elastic();
    my $results = $e->search(
        index => 'perldoc',
        type => ['module','annotation'],
        _source => [ "title","shortdesc","pod","module" ],
        body => {
            %query,
            "aggs" => {
                "namespaces" => {
                    "terms" => { "field" => "namespaces" }
                }
            }
        }
        );
    
    my $out_mod = $results->{hits}{hits};

    foreach my $oa (@$out_mod) {
        if($oa->{_type} eq 'annotation') {
            $oa->{_source}{pa} = Pod::Abstract->load_string("=pod\n\n".$oa->{_source}{pod});
        }
    }
    
    my $columns = 0;
    $columns += 1 if @$out_mod > 0;
    
    my $out = {
        selected => \%selected,
        es_results => $results,
        modules => $out_mod,
        columns => $columns
    };
    
    template "autocomplete.tt",
        { results => $out },
        { layout => undef };
};

sub inbound_links {
    my ($original_doc) = @_;
    
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
    
    return template "links.tt",
        {links => \@out_links},
        {layout => undef};
}

true;
