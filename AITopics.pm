package AITopics;

use strict;
use Exporter;
use JSON -support_by_pp;
use HTTP::Request;
use YAML;
use MIME::Base64;
use Data::Dumper;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = 1.00;
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw($host upload_file update_node process_nodes get_node_by_alias);
%EXPORT_TAGS = (DEFAULT => [qw(upload_file update_node process_nodes get_node_by_alias)]);

my $host;
my $token;
my $session_name;
my $sessid;
my $config;

my $json = JSON->new->utf8;
$json->allow_singlequote();

sub upload_file {
    my $ua = shift;
    my $filename = shift;
    my $tmpfile = shift;

    my $filesize = -s $tmpfile;
    local($/) = undef;
    open(FILE, $tmpfile) or die "$!";
    # use "" as second parameter to prevent linebreaks
    my $encoded = encode_base64(<FILE>, "");
    close(FILE);
    my $json_content = '{"filesize": "'.$filesize.'", "filename": "'.$filename.'", "file": "'.$encoded.'"}';

    my $create_req = HTTP::Request->new(POST => "$host/rest/file");
    $create_req->content_type('application/json');
    $create_req->content($json_content);
    my $resp = $ua->request($create_req);
    if($resp->is_error) {
        print STDERR $resp->message;
        return 0;
    } else {
        my %data = %{$json->decode($ua->{content})};
        return $data{'fid'};
    }
}

sub update_node {
    my $ua = shift;
    my $nid = shift;
    my %data = @_;
    print "Updating $nid ... ";
    print Dumper(\%data);
    my $json_content = $json->encode(\%data);
    my $update_req = HTTP::Request->new(PUT => "$host/rest/node/".$nid);
    $update_req->header('X-CSRF-Token', $token);
    $update_req->header('session', "$session_name=$sessid");
    $update_req->content_type('application/json');
    $update_req->content($json_content);
    my $resp = $ua->request($update_req);
    if($resp->is_error) {
        print STDERR $resp->message;
        return 0;
    } else {
        print "Done.\n";
        return 1;
    }
}

sub get_node_by_alias_edit_link {
    # try grabbing the nid from the edit link (sometimes the url
    # aliases aren't available from the view, presumably due to a bug
    # in views_url_alias module)
    my $ua = shift;
    my $alias = shift;
    print "Trying to grab alias by 'edit' link on node view... ";
    $ua->get("$host/$alias");
    if($ua->{content} =~ m!<a href="/node/(\d+)/edit">Edit</a>!) {
        my $nid = $1;
        print "Answer: $nid\n";
        return $nid;
    } else {
        print "Answer: none\n";
        return '';
    }
}

sub get_node_by_alias {
    my $ua = shift;
    my $alias = shift;
    print "Grabbing nid of alias $alias ... ";
    $ua->get("$host/rest/node-by-alias?alias=$alias");
    my @json_data = @{$json->decode($ua->{content})};
    if($#json_data >= 0) {
        my %node = %{$json_data[0]};
        if($node{'node_title'} ne '') {
            print "Answer: ".$node{'nid'}.".\n";
            return $node{'nid'};
        } else {
            return get_node_by_alias_edit_link($ua, $alias);
        }
    } else {
        return get_node_by_alias_edit_link($ua, $alias);
    }
}

sub process_nodes {
    my $ua = shift;
    my $service = shift;
    my $process_func = shift;
    my $paginated = shift;

    $config = YAML::LoadFile("aitopics.conf");
    $host = $config->{host};

    print STDERR "Logging in...\n";
    my $login_req = HTTP::Request->new(
        POST => "$host/rest/user/login");
    $login_req->content_type('application/json');
    $login_req->content('{"username" : "'.$config->{username}.'",'.
                        ' "password" : "'.$config->{password}.'"}');
    my %resp = %{$json->decode($ua->request($login_req)->{'_content'})};
    $session_name = $resp{'session_name'};
    $sessid = $resp{'sessid'};

    my $token_req = HTTP::Request->new(
        POST => "$host/services/session/token");
    $token_req->content_type('application/json');
    $token_req->content('{"name" : "'.$config->{username}.'",'.
                        ' "pass" : "'.$config->{password}.'"}');
    my $token_resp = $ua->request($token_req);
    $token = $token_resp->decoded_content;

    my @nodes;
    my $page = 0;
    if($#ARGV == 0) { $page = int($ARGV[0]); }
    while (1) {
        if($paginated) {
            print STDERR "Getting page $page\n";
            $ua->get("$host/rest/$service&page=$page");
        } else {
            $ua->get("$host/rest/$service");
        }
        my @json_data = @{$json->decode($ua->{content})};
        if($#json_data >= 0) {
            push(@nodes, @json_data);
            if($paginated) {
                $page++;
            } else {
                last;
            }
        } else {
            last;
        }
    }

    foreach my $i (0..$#nodes) {
        if($i % 100 == 0) { print "\n".($i+1)."/".($#nodes+1)."\n"; }

        my %nid = %{$nodes[$i]};
        $ua->get("$host/rest/node/".$nid{'nid'});
        my %node = %{$json->decode($ua->{content})};

        if($process_func->($ua, %node)) {
            print "{$node{'nid'}}\n";
        } else {
            print ".";
        }
    }
    print STDERR "\n";
}

1;

