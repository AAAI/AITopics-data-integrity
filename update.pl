#!/usr/bin/perl -w

use strict;

use WWW::Mechanize;
use HTTP::Cookies;
use Data::Dumper;
use Getopt::Std;
use Date::Simple ('today');

use AITopics qw(upload_file update_node process_nodes get_node_by_alias);

my %item_types = (
    'link' => '3826',
    'news' => '3827',
    'podcast' => '3828',
    'publication' => '3829',
    'video' => '3830');

$| = 1;

sub correct_local_link {
    my $ua = shift;
    my (%node) = @_;

    if(UNIVERSAL::isa($node{'field_original_link'}, "HASH")) {
        if($node{'field_original_link'}{'und'}[0]{'url'} =~ m!^/!) {
            $node{'field_original_link'}{'und'}[0]{'url'} =~ s!^/+!http://aitopics.org/!;
            return update_node($ua, %node);
        } elsif($node{'field_original_link'}{'und'}[0]{'url'} =~ m!^sites/default/files!) {
            $node{'field_original_link'}{'und'}[0]{'url'} = "http://aitopics.org/" .
                $node{'field_original_link'}{'und'}[0]{'url'};
            return update_node($ua, %node);
        }
    }
    return 0;
}

sub check_title_in_primary_link {
    my $ua = shift;
    my (%node) = @_;

    if($node{'node_sticky'} != "1") {
        my $resp = $ua->get($node{'Primary link'});
        my @title_words = split(/\s+/, $node{'node_title'});
        if($resp->is_success) {
            my $found = 0;
            foreach my $title_word (@title_words) {
                if($ua->{'content'} =~ m/\Q$title_word\E/im) {
                    $found++;
                }
            }
            if($found < (($#title_words+1) / 2)) {
                return unpublish_node($node{'nid'}, "{\"status\": null}");
            }
        } else {
            return unpublish_node($node{'nid'}, "{\"status\": null}");
        }
    }
    return 0;
}

sub process_link {
    my $ua = shift;
    my (%node) = @_;
    my $result = 0;

    #$result |= correct_local_link($ua, %node);

    #$result |= check_title_in_primary_link($ua, %node);

    #print Dumper(\%node);

    return $result;
}

sub process_item {
    my $ua = shift;
    my (%node) = @_;
    my $result = 0;

    if(ref($node{'Publication date'}) ne 'ARRAY') {
        my $year = substr($node{'Publication date'}, 0, 4);
        if($node{'Publication Year'} ne $year) {
            my $json_content = '{"field_publication_year_int": {"und": [{"value": "'.$year.'"}]}}';
            $result |= update_node($ua, $node{'nid'}, $json_content);
        }
    }
}

sub process_video {
    my $ua = shift;
    my (%node) = @_;
    my $result = 0;

    # update representative images from youtube if missing
    if(ref($node{'Representative image'}) eq 'ARRAY') {
        my $youtube;
        if($node{'Primary link'} =~ m!http://youtu\.be/(.*)!) {
            $youtube = $1;
        } elsif($node{'Primary link'} =~ m!http://www\.youtube\.com/watch\?v=(.*?)&!) {
            $youtube = $1;
        } elsif($node{'Primary link'} =~ m!http://www\.youtube\.com/watch\?v=(.*)!) {
            $youtube = $1;
        }
        if($youtube) {
            my $img = "http://img.youtube.com/vi/$youtube/1.jpg";
            # retrieve image
            my $resp = $ua->get($img, ":content_file" => "/tmp/1.jpg");
            if($resp->is_success) {
                # post to aitopics as a file upload
                my $fid = upload_file($ua, "youtube-thumbnail-".$node{'nid'}.".jpg",
                                      "/tmp/1.jpg");
                if($fid != 0) {
                    my $json_content = '{"field_representative_image": {"und": [{"fid": '.$fid.', "display": "1", "width": "120", "height": "90"}]}}';
                    $result |= update_node($ua, $node{'nid'}, $json_content);
                }
            } else {
                print STDERR "Failed to download $img into /tmp/1.jpg";
                return 1;
            }
        }
    }

    return $result;
}

sub promote_top_nodes {
    my $ua = shift;
    my $today = today();
    my $week_back = $today - 7;
    my $analytics_output = `python top_nodes.py $week_back $today`;
    my $i = 0;
    foreach my $line (split(/\n/, $analytics_output)) {
        if($i >= 6) { last; }
        else {
            my ($url) = ($line =~ m!\(\d+/\d+\) /(.*$)!);
            my $nid = get_node_by_alias($ua, $url);
            if($nid ne '') {
                update_node($ua, $nid, '{"promote": "1", "field_sort_weight": {"und": [{"value": "'.$i.'"}]}}');
                $i++;
            }
        }
    }

}

sub process_front_page {
    my $ua = shift;
    my (%node) = @_;
    my $result = 0;

    # unpublish every front page node
    $result = update_node($ua, $node{'nid'}, '{"promote": null}');
}

sub process_topic {
    my $ua = shift;
    my (%node) = @_;
    my $result = 0;

    my @issues;

    if(ref($node{'Representative image'})) {
        push(@issues, "Missing representative image");
    }
    if(ref($node{'Body'}) || length($node{'Body'}) < 1000) {
        push(@issues, "Short or missing summary");
    }
    if(!ref($node{'Body'}) && ($node{'Body'} =~ m/href="#[^"]+"/ ||
                               $node{'Body'} =~ m/aitopics\.net/)) {
        push(@issues, "Internal links to old site in summary");
    }
    if(!ref($node{'Body'})) {
        while($node{'Body'} =~ m/href="(.*?)"/g) {
            my $url = $1;
            my $resp = $ua->get($url);
            if(!$resp->is_success) {
                $resp = $ua->get("http://aitopics.org$url");
                if(!$resp->is_success) {
                    push(@issues, "Broken links in summary");
                    last;
                }
            }
        }
    }
    if(ref($node{'Meta-keywords'}) || ref($node{'Meta-description'})) {
        push(@issues, "Missing meta-keywords or meta-description");
    }

    if(@issues) {
        my $json_content = "{\"field_quality_control_issues\": {\"und\": {\"select\": [";
        foreach my $i (0..$#issues) {
            my $issue = $issues[$i];
            $json_content .= "\"$issue\"";
            if($i < $#issues) {
                $json_content .= ",";
            }
        }
        $json_content .= "]}}}";
        update_node($ua, $node{'nid'}, $json_content);

        $result = 1;
    }

    return $result;
}

$Getopt::Std::STANDARD_HELP_VERSION = 1;

sub HELP_MESSAGE {
    my $fh=$_[0];
    print $fh "AITopics data integrity.
    -t for topic updates
    -v for video updates
    -l for link updates
    -i for all item updates (e.g., year fixes)
    -f to update the front page
";
}

sub VERSION_MESSAGE {
    my $fh=$_[0];
    #print $fh "\n";
}

sub run {
    my $ua = WWW::Mechanize->new(
        autocheck => 0, 
        cookie_jar => HTTP::Cookies->new(file => "cookies.txt"));

    my %opts = ();
    getopts('tvlif', \%opts);

    if(length(%opts) > 1) {
        if(exists($opts{'t'})) {
            process_nodes($ua, "topics", \&process_topic);
        }
        if(exists($opts{'v'})) {
            process_nodes($ua, "items?item_type=$item_types{'video'}", \&process_video);
        }
        if(exists($opts{'l'})) {
            process_nodes($ua, "items?item_type=$item_types{'link'}", \&process_link);
        }
        if(exists($opts{'i'})) {
            process_nodes($ua, "items", \&process_item);
        }
        if(exists($opts{'f'})) {
            process_nodes($ua, "front-page", \&process_front_page);
            promote_top_nodes($ua);
        }
    } else {
        HELP_MESSAGE(*STDOUT);
    }
}

run;

