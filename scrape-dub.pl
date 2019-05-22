#!/usr/bin/env perl

use strict;
use warnings;

use Date::Parse;
use LWP::UserAgent;
use Web::Scraper;
use URI;
use HTTP::Request;

my %urls = (
  'Train to Skavilile' => 'http://www.traintoskaville.org/thoughtconduit/archives?grid=9',
  'Dancehall Reggae'   => 'http://www.dancehallreggae.org/thoughtconduit/archives?grid=16',
);
my $root = '/mnt/media/Music/Radio';

my $index = scraper {
    process 'h1.listItemTitleString a', 'hrefs[]' => '@href';
};

my $detail = scraper {
    process 'span.itemSubjectString',   title => 'text';
    process 'span.archiveCreationDate', date  => 'text';
    process 'span.itemSynopsisString',  desc  => 'text';
    process 'audio source',             url   => '@src';
    process 'div.metadataDiv a.fancy',  dl    => '@href';
};

my $ua = LWP::UserAgent->new( cookie_jar => {} );

FETCH:
for my $name ( keys %urls ) {
    my $url = $urls{$name};
    warn "===> Fetching $name [$url]\n";

    my $res = $ua->get($url);
    if ($res->code != 200) {
        die "Index error: ", $res->content;
    }

    my $item_hrefs = $index->scrape($res->content);

    for my $item_href ( @{ $item_hrefs->{hrefs} } ) {
        my $item_uri = URI->new($url);
        $item_uri->path_query($item_href);

        warn "===> Fetching $item_uri\n";

        my $res = $ua->get($item_uri);
        if ($res->code != 200) {
            die "Item error: ", $res->content;
        }

        my $item = $detail->scrape($res->content);

        if ($item->{dl}) {
            my $file_uri = URI->new($url);
            $file_uri->path_query($item->{dl});

            $item->{date} =~ s/^\s+//;
            $item->{date} =~ s/\s+$//;

            my ($ss,$mm,$hh,$d,$m,$y,$z) = strptime($item->{date});
            $y += 1900;
            my $dir = sprintf '%s/%s/%04d', $root, $name, $y;
            system 'mkdir', '-p', $dir;

            my $path = sprintf '%s/%02d-%02d-%04d.mp3', $dir, $m, $d, $y;
            warn "===> Downloading $path\n";

            next if -e $path;

            my $req = HTTP::Request->new( GET => $file_uri );
            my $res = $ua->request($req, $path);
            if ($res->is_success) {
              system 'mp3info', '-a', 'WCBN', '-l', $name, '-t', $item->{date}, '-y', $y, $path;
            }
            else {
              unlink $path;
            }
        }
    }
}

sleep 60 * 60 * 12;
goto FETCH;
