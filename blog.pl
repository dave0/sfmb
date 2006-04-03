#!/usr/bin/perl -w
use strict;
use warnings;
use CGI qw( :standard );
use IO::File;
use File::Find::Rule;

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


my $articles = Article->list( $conf );
my @article_keys = reverse sort keys %$articles;

for( path_info() ) {
	m!/(\d{14})$! && do {
		my $key = $1;
		if( exists $articles->{$key} ) {
			@article_keys = ( $key );
		}
		last;
	};
	m!/feed.xml$! && do {
		print header('application/rss+xml'),
		      xml_articles({ 
				conf => $conf, 
				articles => [ map { $articles->{$_} } @article_keys ]
		});
		exit(0);
	};
}

print header,
	top({ 
		conf => $conf,
		article_title => $articles->{ $article_keys[0] }->{subject}
	}),
	sidebar({ 
		conf => $conf, 
		articles => [ map { $articles->{$_} } reverse sort keys %$articles ]
	}),
	articles({ 
		conf => $conf, 
		articles => [ map { $articles->{$_} } @article_keys ]
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
	   ->name( qr/^\d{14}$/ );
	
	if( exists $args->{date_start} ) {
		$find->mtime( '>=' .  $args->{date_start}->epoch );
	} else {
		$find->mtime( '>=' . DateTime->now->subtract( months => 6)->epoch);
	}
	
	if( exists $args->{date_end} ) {
		$find->mtime( '<=' .  $args->{date_end}->epoch );
	} else {
		$find->mtime( '<=' . DateTime->now->epoch);
	}

	return { map { my $a = $class->new({filename => $_}); ($a->{key}, $a) } $find->in( $args->{data_dir}) };
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

package main;

__DATA__
__TT__
[% BLOCK top %]
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
        "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <title>[% article_title ? article_title : conf.title %]</title>
    <meta name="ICBM" content="[% conf.meta.ICBM %]" /> 
    <meta name="geo.region" content="[% conf.meta.geo.region %]" /> 
    <meta name="geo.placename" content="[% conf.meta.geo.placename %]" /> 
    <link rel="alternate" type="application/rss+xml" title="RSS" href="[% conf.url_base %]/feed.xml" /> 
    <link rel="stylesheet" type="text/css" media="all" href="[% conf.url_base %]/blog.css" />
  </head>
  <body>
    <h1><a href="[% conf.url_base %]">[% conf.title %]</a></h1>
[% END %]

[% BLOCK bottom %]
  </body>
</html>
[% END %]


[% BLOCK article %]
[% USE date %]
<div class='article'>
  <h2>[% article.subject %]</h2>
  <h4> [ link: <a href='[% conf.url_base %]/[% article.key %]'>[% article.key %]</a> | updated: [% date.format(article.mtime, '%a, %d  %b  %Y  %H:%M:%S  %z') %] ]</h4>
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
[% FOREACH article = articles %]
[ <a href="[% conf.url_base %]/[% article.key %]">[% article.key %]</a> ]<br />[% article.subject %]<br />
<br />
[% END %]
<p>
<a href="http://validator.w3.org/check?uri=referer"><img
      src="http://www.w3.org/Icons/valid-xhtml10"
      alt="Valid XHTML 1.0 Transitional" height="31" width="88" border="0"/></a>
</p>
<p>
<a href="http://www.vim.org"><img
      src="/images/vim/vim_created.gif"
      alt="Created with Vim" height="36" width="90" border="0"/></a>
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

h1, h2 { 
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
	background-color: #ffffee;
	text-align: right;
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
