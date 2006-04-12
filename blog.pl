#!/usr/bin/perl -w
use strict;
use warnings;
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

print header,
	top({ 
		conf    => $conf,
		title   => (scalar(@current_articles) == 1) 
		            ? $articles{ $current_articles[0] }->{subject} . " - $conf->{title}"
			    : $conf->{title},
		current => path_info(),
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

	return $formats->{$self->{'content-type'}}->($self->{body})
	    if exists $formats->{$self->{'content-type'}};
}

sub tags
{
	my ($self) = @_;
	if( exists $self->{tags} ) {
		return split(/\s*,\s*/,$self->{tags});
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
    [% IF current %]<h4>Now viewing: <a href="[% conf.url_base %][% current %]">[% current %]</a></h4>[% END %]
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
<a href="http://www.vim.org"><img
      src="/img/vim_the_editor.png"
      alt="Created with Vim" height="15" width="80" border="0"/></a>
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

#sidebar h3 {
	font-size: 12pt;
	margin-left: -10px;
	margin-bottom: 0;
}

h4 {
	margin-top: 0;
	font-size: 10pt;
	font-weight: normal;
	text-align: right;
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

#sidebar {
	float: left;
	width: 160px;
	margin: 0;
	padding: 1em;
}


[% END %]

[% BLOCK xml_articles %]
[% USE date %]
<rss version="0.92" xml:base="[% conf.url_base %]">
  <channel>
    <title>[% conf.title %]</title>
    <link>http://[% conf.host_name %][% conf.url_base %]</link>
    <description></description>
    <language>en</language>

    [% FOREACH item = articles %]
    <item>
      <title>[% item.subject %]</title>
      <link>http://[% conf.host_name %][% conf.url_base %]/[% item.key %]</link>
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
