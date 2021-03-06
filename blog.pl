#!/usr/bin/perl -w
use strict;
use warnings;
use English qw( -no_match_vars );
use CGI qw( :standard );
use IO::File;
use File::Find::Rule;
use POSIX qw( strftime );

use Inline TT => 'DATA';

my $conf = {
	title    => 'Blog',
	data_dir => '/home/dmo/.blog/entries',
	timezone => 'Canada/Eastern',
	url_base => script_name(),
	host_name => virtual_host(),

	# fix me: don't know how to pass the fact that we are viewing one
	# article into formatted_body()
	hack_single => 0,

	# Maximum number of articles per page.  0 disables pagination
	articles_per_page => 10,
	
	meta      => {

		# See http://geourl.org/
		ICBM => '45.36642,-75.74261',
		
		# See http://geotags.com/
		geo  => {
			region    => 'CA.ON',
			placename => 'Ottawa',
		},
	}
};

if( scalar @ARGV ) {
	eval "use Getopt::Long";
	if( $EVAL_ERROR ) {
		die q{Commandline mode needs Getopt::Long, but it was not found};
	}

	my ($preview, $render);
	my $result = GetOptions ( "preview=s" => \$preview,
	                          "render=s"  => \$render, );

	if( ! $result ) {
		die q{invalid arguments};
	}

	if( $preview ) {
		die q{preview not written yet.  bug dmo.};
	} elsif( $render ) {
		path_info( $render );
	}
}


# Check for CSS first before reading article files
for( path_info() ) {
	m!/blog.css$! && do {
		print header('text/css');
		print stylesheet({});
		exit(0);
	};
}


my %articles = %{Article->load_many({
	data_dir => $conf->{data_dir}
}) };


my @all_articles = reverse sort grep { /^\d{14}$/ } keys %articles;
my %tagged_articles;
foreach my $key ( @all_articles ) {
	foreach my $tag ( $articles{$key}->tags ) {
		$tagged_articles{$tag} = () unless exists $tagged_articles{$tag};
		push @{$tagged_articles{$tag}}, $key;
	}
}
my @current_articles;

# Handle pagination
my $current_page = param('page') || 1;
$current_page =~ s/[^\d]//g; # sanitize.


for( path_info() ) {

	# Produce feed
	m!^/feed.xml$! && do {
		my $latest = $all_articles[0];
		# TODO: handle Conditional GET by checking ETag and Last-Modified: headers and return 304 if no change
		print header(
			  -type => 'application/rss+xml',
			  -etag => qq{"$latest"},
			  -last_modified => strftime("%a, %d %b %Y %H:%M:%S %Z", (gmtime($articles{$latest}->{mtime}))),
			  -whatever => $articles{$latest}{mtime},
		      ),
		      xml_articles({ 
				conf => $conf, 
				articles => [ @articles{ @all_articles } ]
		});
		exit(0);
	};

	# Handle tags
	m!^/(r?)tag/([^/]+)$! && do {
		my $reversed = $1;
		my $tag = $2;
		if( exists $tagged_articles{$tag} ) {
			@current_articles = @{ $tagged_articles{ $tag } };
			@current_articles = reverse @current_articles if $reversed;
			last;
		}
		print header(
			-type   => 'text/html',
			-status => '404 File Not Found' ),
		      error_404( { conf => $conf, entry_name => $_ } );
		exit(0);
	};

	# Handle date-based searches
	m!^/date/(\d{4})/?(\d{2})?/?(\d{2})?$! && do {
		my ($yy,$mm,$dd) = ($1,$2,$3);
		
		my %what = defined $dd ? ( days   => 1 )
			 : defined $mm ? ( months => 1 )
			 :               ( years  => 1 );
		my $dur   = DateTime::Duration->new( %what );

		$mm ||= 1;
		$dd ||= 1;
		my $start = DateTime->new( year => $yy, month => $mm, day => $dd );
		$start->set_time_zone( $conf->{timezone} );
		
		my $extra = Article->load_many({
			data_dir   => $conf->{data_dir},
			date_start => $start->epoch,
			date_end   => ($start + $dur)->epoch,
		});
		
		@current_articles = grep { /^\d{14}$/ } keys %$extra;
		for my $key ( @current_articles ) { 
			$articles{$key} = $extra->{$key} unless exists $articles{$key};
		}
		last;
	};

	# Handle single article
	m!^/([^/]+)$! && do {
		my $key = $1;
		if( exists $articles{$key} ) {
			@current_articles = ( $key );
			$conf->{hack_single} = 1;
			last;
		}
		print header(
			-type   => 'text/html',
			-status => '404 File Not Found' ),
		      error_404( { conf => $conf, entry_name => $_ } );
		exit(0);
	};

	# Handle list page by default
	@current_articles = @all_articles;
	
}

if( $conf->{articles_per_page} ) {
	
	# Slight hack...
	$conf->{total_matching_articles} = scalar @current_articles;
	$conf->{prev_article_count} = ($current_page - 1) * $conf->{articles_per_page};

	# Technically, this would be best done with an array slice, but
	# splice() is so much cleaner and more readable than mucking about with
	# @stuff[$foo .. $bar]
	@current_articles = splice(
		@current_articles,
		$conf->{prev_article_count},
		$conf->{articles_per_page});

	# Slight hack...
	$conf->{articles_on_page} = scalar @current_articles;
	$conf->{next_article_count} = $conf->{total_matching_articles} - ($conf->{articles_on_page} + (($current_page - 1) * $conf->{articles_per_page}));

}

print header,
	top({ 
		conf    => $conf,
		title   => (scalar(@current_articles) == 1) 
		            ? $articles{ $current_articles[0] }->{subject} . " - $conf->{title}"
			    : $conf->{title},
		current => path_info(),
		prev_page => ($conf->{prev_article_count} > 0) ? $current_page - 1 : 0,
		next_page => ($conf->{next_article_count} > 0) ? $current_page + 1 : 0,
	}),
	sidebar({ 
		conf     => $conf, 
		articles => [ @articles{ @all_articles } ],
		tags     => [ 
			map +{ name => $_, weight => scalar @{$tagged_articles{$_}} }, keys %tagged_articles
		]
	}),
	articles({ 
		conf     => $conf, 
		articles => [ @articles{ @current_articles } ]
	}),
	bottom({});

exit(0);

package Article;
use File::Basename;
use DateTime;
use Text::Markdown 'markdown';

sub new 
{
	my ($class, $args) = @_;

	$args->{key}   = basename( $args->{filename} );

	my $self = bless $args, $class;

	$self->load();
	
	return $self;
}

sub load
{
	my ($self) = @_;

	my $fh = new IO::File $self->{filename}, 'r';
	if( ! defined $fh ) {
		die "Couldn't open $self->{filename}";
	}

	while( my $line = <$fh> ) {
		chomp;
		last if $line !~ /:/;
		last if $line =~ /^$/;
		my ($key, $value) = $line =~ m/\s*([^\s:]+):\s*(.*?)\s*$/;
		$self->{lc $key} = $value;
	}

	{ 
		local $/;
		$self->{body} = <$fh>;
	}
	close $fh;

	my $date = DateTime->from_epoch( epoch => (stat($self->{filename}))[9]);
	$date->set_time_zone( $conf->{timezone} );
	$self->{mtime} = $date->epoch;

	if( ! exists $self->{'content-type'} ) {
		if( $self->{body} =~ /^</ ) {
			$self->{'content-type'} = 'text/html';
		} else {
			$self->{'content-type'} = 'text/plain';
		}
	}

        if ($self->{'content-type'} eq 'text/x-markdown') {

                my $base = $conf->{url_base};

                # convert [text]{anything} to [text]($url_base/anything) which
                # makes markdown generate <a href=$url_base/anything>text</a>
                $self->{body} =~ s!(\[[^\]]+\])\{([^\}]+)\}!$1($base/$2)!g;
        }
}

sub list
{
	my ($class, $args) = @_;
	my $find = File::Find::Rule->new()
	   ->file
	   ->nonempty
	   ->readable
	   ->maxdepth(1)
	   ->name( qr/^\d{14}$/ )
	   ->mtime( '<=' .  time() );

	return $find->in($args->{data_dir});
}

sub load_many
{
	my ($class, $args) = @_;

	$args->{date_start} ||= DateTime->now->subtract( months => 6)->epoch;
	$args->{date_end}   ||= DateTime->now->epoch;

	my $find = File::Find::Rule->new()
	   ->file
	   ->nonempty
	   ->readable
	   ->maxdepth(1)
	   ->name( qr/^\d{14}$/ )
	   ->mtime( '>=' .  $args->{date_start} )
	   ->mtime( '<=' .  $args->{date_end} );

	my %articles;
	foreach ( $find->in($args->{data_dir}) ) {
		my $a = $class->new({filename => $_}); 
		$articles{$a->{key}}   = $a;
		$articles{$a->{alias}} = $a if exists $a->{alias};
	}

	return \%articles;
}

sub formatted_body 
{
	my ($self) = @_;
	my $formats = { 
		'text/plain'      => sub { return "<pre>$_[0]</pre>" },
		'text/html'       => sub { return $_[0] },
		'text/x-markdown' => sub { return markdown($_[0]) },
	};

	my $out = $formats->{$self->{'content-type'}}->($self->{body})
	    if exists $formats->{$self->{'content-type'}};

	# convert ^<read-more>$ and everything that follows 
	# to a Read More link
	if (not $conf->{hack_single}) {
                my $base = $conf->{url_base};
		my $key  = $self->{alias} ? $self->{alias} : $self->{key};
		my $link = "<a href=$base/$key>[Read More]</a>";
		$out =~ s!((<br>|<p>))\s*<read-more>\s*((<br>|</p>)).*$!\n$1$link$2!s;
	} else {
		$out =~ s!(<br>|<p>)\s*<read-more>\s*(<br>|</p>)!\n!s;
	}

	return $out;
}

sub tags
{
	my ($self) = @_;
	if( exists $self->{tags} ) {
		my %unique;
		return grep { ++$unique{$_} == 1 } split(/\s*,\s*/,$self->{tags});
	}
}

package main;

__DATA__
__TT__
[% BLOCK top %]
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <title>[% title %]</title>
    <meta name="ICBM" content="[% conf.meta.ICBM %]" /> 
    <meta name="geo.region" content="[% conf.meta.geo.region %]" /> 
    <meta name="geo.placename" content="[% conf.meta.geo.placename %]" /> 
    <link rel="alternate" type="application/rss+xml" title="RSS" href="[% conf.url_base %]/feed.xml" /> 
    <link rel="stylesheet" type="text/css" media="all" href="[% conf.url_base %]/blog.css" />
  </head>
  <body>
    <h1><a href="[% conf.url_base %]">[% conf.title %]</a></h1>
    <div id="navbar">
    [% IF prev_page %]<a id="prev" href="[% conf.url_base %][% current %]?page=[% prev_page %]" title="See previous [% conf.articles_per_page %] (of [% conf.prev_article_count %] before this one)">&laquo;</a>[% END %]
    [% IF current %]<a id="current" href="[% conf.url_base %][% current %]">[% current %]</a></h4>[% END %]
    [% IF next_page %]<a id="next" href="[% conf.url_base %][% current %]?page=[% next_page %]" title="See next [% (conf.articles_per_page > conf.next_article_count) ? conf.next_article_count : conf.articles_per_page %] (of [% conf.next_article_count %] after this one)">&raquo;</a>[% END %]
    </div>
[% END %]

[% BLOCK bottom %]
  </body>
</html>
[% END %]


[% BLOCK article %]
[% USE date %]
<div class='article'>
  <h2>[% article.subject %]</h2>
  <h4>[ link: <a href='[% conf.url_base %]/[% article.alias ? article.alias : article.key %]'>[% article.alias ? article.alias : article.key %]</a> 
  | tags:
  [% FOREACH tag = article.tags %]
      <a href='[% conf.url_base %]/tag/[% tag %]'>[% tag %]</a>
  [% END %]
  | updated: [% date.format(article.mtime, '%a, %d  %b  %Y  %H:%M:%S  %z') %] ]</h4>
  <div class='article_body'>
	[% article.formatted_body ? article.formatted_body : article.body %]
  </div>
</div>
[% END %]

[% BLOCK articles %]
<div class="content">
[% FOREACH article = articles %]
[% PROCESS article %]
[% END %]
</div>
[% END %]

[% BLOCK sidebar %]
<div id="sidebar">
<h3>Tags</h3>
[% FOREACH tag = tags %]
<span style='font-size: [% tag.weight + 10 %]pt'><a href="[% conf.url_base %]/tag/[% tag.name %]">[% tag.name %]</a></span>
[% END %]

<h3>Posts</h3>
[% FOREACH article = articles %]
<p>
   [ <a href="[% conf.url_base %]/[% article.key %]">[% article.key %]</a> ]<br />[% article.subject %]
</p>
[% END %]
<p>
<a href="[% conf.url_base %]/feed.xml"><img
      src="/img/rss_fullposts.png"
      alt="RSS Feed - Full Content" height="15" width="80" border="0"/></a>
</p>
<p>
<a href="http://validator.w3.org/check?uri=referer"><img
      src="/img/valid_xhtml10.png"
      alt="Valid XHTML 1.0 Transitional" height="15" width="80" border="0"/></a>
</p>
<p>
<a href="http://www.perl.org"><img
      src="/img/perl.png"
      alt="Created with Perl" height="15" width="80" border="0"/></a>
</p>
</div>
[% END %]

[% BLOCK stylesheet %]
body { 
	color: black;
	background: white;
	font-size: 10pt;
	padding-left: 6%;
	padding-right: 6%;
}

h1, h2, h3 { 
	font-family: lucida, verdana, helvetica, arial, sans-serif;
	font-style: normal;
	font-variant: normal;
	font-weight: bolder;
}

h1 {
	color: #039;
}

h1 a {
	text-decoration: none;
	color: #039;
}

h2 {
	border-bottom: 1px solid black; 
	border-top: 1px solid black;
	background-color: #ffffcc;
	margin-bottom: 0;
}

h4 {
	margin-top: 0;
	font-size: 10pt;
	font-weight: normal;
	text-align: right;
}

#sidebar {
	float: left;
	width: 160px;
	margin: 0;
	padding: 1em;
}

#sidebar h3 {
	font-size: 12pt;
	margin-left: -10px;
	margin-bottom: 0;
}

#navbar {
	margin-top: 0;
	margin-left: 200px;
	text-align: right;
}

#navbar #current {
	font-size: 10pt;
	font-weight: normal;
}

#navbar #prev {
	text-decoration: none;
	font-size: 14pt;
	font-weight: normal;
}

#navbar #next {
	text-decoration: none;
	font-size: 14pt;
	font-weight: normal;
}

.article h4 {
	background-color: #ffffee;
}

.content {
	margin-left: 200px;
}

.article_body {
	padding-left: 20px;
}


[% END %]

[% BLOCK xml_articles %]
[% USE date %]
<rss version="0.92" xml:base="[% conf.url_base %]">
  <channel>
    <title>[% conf.title | html_entity %]</title>
    <link>http://[% conf.host_name %][% conf.url_base %]</link>
    <description></description>
    <language>en</language>

    [% FOREACH item = articles %]
    <item>
      <title>[% item.subject | html_entity %]</title>
      <link>http://[% conf.host_name %][% conf.url_base %]/[% item.key %]</link>
      [% FOREACH tag = item.tags %]
          <category>[% tag %]</category>
      [% END %]
      <description>
	<![CDATA[ [% item.formatted_body ? item.formatted_body : item.body %]
      ]]></description>
      <pubDate>[% date.format(item.mtime, '%a, %d  %b  %Y  %H:%M:%S  %Z') %]</pubDate>
    </item>
    
    [% END %]
  </channel>
</rss>
[% END %]

[% BLOCK error_404 %]
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<HTML><HEAD>
<TITLE>404 Not Found</TITLE>
</HEAD><BODY>
<H1>Not Found</H1>
The blog entry [% entry_name | html_entity %] was not found.
</BODY></HTML>
[% END %]
