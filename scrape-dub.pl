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
        my $ua = LWP::UserAgent->new( cookie_jar => {} );
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

            for my $f (qw(date title)) {
              $item->{$f} =~ s/^\s+//;
              $item->{$f} =~ s/\s+$//;
            }

            my ($ss,$mm,$hh,$d,$m,$y,$z) = strptime($item->{date});
            $y += 1900;
            my $dir = sprintf '%s/%s/%04d', $root, $name, $y;
            system 'mkdir', '-p', $dir;

            $ua->add_handler(
              response_header => sub {
                my ($res, $ua, $handler) = @_;

                return unless $res->code == 200;

                my $type = $res->header('content-type');
                my $disposition = $res->header('content-disposition');

                if (!$disposition) {
                  use Data::Dumper;
                  warn Dumper($res);
                  warn $res->content;
                  die;
                }

                my @parts = split ';', $disposition;
                my %kv;
                for my $p (@parts) {
                  my ($k, $v) = split '=', $p;
                  $kv{$k} = $v;
                }

                my $file = $kv{filename};
                my $path = "$dir/$file";

                die "File exists" if -e $path;

                warn "===> Writing to $path\n";

                open my $fh, '>', "$path.tmp" or die "Unable to open $path: $!";

                $ua->add_handler(
                  response_data => sub {
                    my ($res, $ua, $handler, $data) = @_;
                    print $fh $data;
                  }
                );

                $ua->add_handler(
                  response_done => sub {
                    my ($res, $ua, $handler) = @_;
                    close $fh;
                    if ($res->code == 200) {
                      warn "===> Tagging $path\n";
                      my %tags = (
                        album  => $name,
                        date   => sprintf("%02d%02d", $d+1, $m+1),
                        year   => $y,
                        title  => $item->{title},
                        artist => 'WCBN',
                        author => 'WCBN',
                        show   => $name,
                      );
                      system 'ffmpeg', '-i', "$path.tmp", '-c:a', 'copy', map({ ('-metadata', "$_=$tags{$_}") } keys %tags), $path;
                      system 'rm', "$path.tmp";
                    }
                    else {
                      unlink $fh;
                    }
                  }
                );
              }
            );

            warn "===> Fetching file for $item->{title}\n";

            my $req = HTTP::Request->new( GET => $file_uri );
            my $res = $ua->request($req);
        }
    }
}

sleep 60 * 60 * 12;
goto FETCH;
