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
@EXPORT_OK   = qw(upload_file update_node process_nodes get_node_by_alias);
%EXPORT_TAGS = (DEFAULT => [qw(upload_file update_node process_nodes get_node_by_alias)]);


my $json_decoder = JSON->new->utf8;
$json_decoder->allow_singlequote();

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

    my $create_req = HTTP::Request->new(POST => "http://aitopics.org/rest/file");
    $create_req->content_type('application/json');
    $create_req->content($json_content);
    my $resp = $ua->request($create_req);
    if($resp->is_error) {
        print STDERR $resp->message;
        return 0;
    } else {
        my %data = %{$json_decoder->decode($ua->{content})};
        return $data{'fid'};
    }
}

sub update_node {
    my $ua = shift;
    my $nid = shift;
    my $json_content = shift;
    print "Updating $nid:\n\n$json_content\n\n";
    my $update_req = HTTP::Request->new(PUT => "http://aitopics.org/rest/node/".$nid);
    $update_req->content_type('application/json');
    $update_req->content($json_content);
    my $resp = $ua->request($update_req);
    if($resp->is_error) {
        print STDERR $resp->message;
        return 0;
    } else {
        return 1;
    }
}

sub get_node_by_alias {
    my $ua = shift;
    my $alias = shift;
    $ua->get("http://aitopics.org/rest/node-by-alias?alias=$alias");
    my @json_data = @{$json_decoder->decode($ua->{content})};
    my %node = %{$json_data[0]};
    if($node{'node_title'} ne '') {
        return $node{'nid'};
    } else {
        return '';
    }
}

sub process_nodes {
    my $ua = shift;
    my $service = shift;
    my $process_func = shift;

    my $config = YAML::LoadFile("aitopics.conf");

    print STDERR "Logging in...\n";
    my $login_req = HTTP::Request->new(
        POST => "http://aitopics.org/rest/user/login");
    $login_req->content_type('application/json');
    $login_req->content('{"username" : "'.$config->{username}.'",'.
                        ' "password" : "'.$config->{password}.'"}');
    my $resp = $ua->request($login_req);

    my @nodes;
    my $page = 0;
    if($#ARGV == 0) { $page = int($ARGV[0]); }
    while (1) {
        print STDERR "Getting page $page\n";
        $ua->get("http://aitopics.org/rest/$service&page=$page");
        my @json_data = @{$json_decoder->decode($ua->{content})};
        if($#json_data >= 0) {
            push(@nodes, @json_data);
            $page++;
        } else {
            last;
        }
    }

    foreach my $i (0..$#nodes) {
        if($i % 100 == 0) { print "\n".($i+1)."/".($#nodes+1)."\n"; }

        my %node = %{$nodes[$i]};

        if($process_func->($ua, %node)) {
            print "{$node{'nid'}}";
        } else {
            print ".";
        }
    }
    print STDERR "\n";
}

1;

