package PAWS;
use Dancer ':syntax';

use Pod::Abstract;
use File::Find;
use Pod::Abstract::Filter::summary;
use Pod::Abstract::Filter::overlay;
use Pod::Abstract::Filter::uncut;
use Pod::Abstract::Filter::sort;
use POSIX qw(strftime);
use PodSummary;
use PAWS::Indexer;
use Pod::Abstract::BuildNode qw(node);
use Digest::MD5 qw(md5_hex);
use Search::Elasticsearch;

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
    $name = $key unless $name;

    my $anno = load_annotations($name);
    merge_annotations($pa, $anno);

    my $content = template "display_module.tt", 
        { title => $name, sub => $subtitle, pa => $pa }, 
        {layout => undef};
    
    my $summ = PodSummary->new->filter($pa);
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
        my @headings = $pa->select('//[@heading]');
        foreach my $head(@headings) {
            my ($hdg) = $head->select('@heading');
            my $hdg_text = $hdg->text;
            
            if($hdg_text eq $section) {
                $section_target = $head->serial;
                last;
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

    $results = $e->search(
        index => 'perldoc',
        type => 'annotation',
        _source => [ "module","pod" ],
        body => {
            query => {
                multi_match => {
                    query => $terms,
                    fields => ["pod"]
                }
            }
        }
        );
    my $out_anno = [ map { $_->{_source} } @{$results->{hits}{hits}} ];
    foreach my $oa (@$out_anno) {
        $oa->{pa} = Pod::Abstract->load_string("=pod\n\n".$oa->{pod});
    }
    my $columns = 0;
    $columns += 1 if @$out_anno > 0;
    $columns += 1 if @$out_fn > 0;
    $columns += 1 if @$out_mod > 0;
    
    my $out = {
        functions => $out_fn,
        modules => $out_mod,
        annotations => $out_anno,
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
