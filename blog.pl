#!/usr/bin/perl -w
use strict;
use warnings;
use CGI qw( :standard );
use IO::File;
use File::Find::Rule;

use Inline TT => 'DATA';

my $conf = {
	title    => 'Whatever Blog',
	data_dir => '/home/dmo/.blog/entries',
	timezone => 'Canada/Eastern',
	url_base => $ENV{SCRIPT_NAME}
};

my $articles = Article->list( $conf );

my $articlekey;
if( exists $ENV{PATH_INFO} ) {
	if( $ENV{PATH_INFO} =~ m!/(\d{14})$! ) {
		$articlekey = $1;
	} elsif ( $ENV{PATH_INFO} =~ m!/blog.css$!) {
		print header('text/css');
		print stylesheet();
		exit(0);
	}
}

my $extra_title = '';
if( defined $articlekey && exists $articles->{$articlekey} ) {
	$extra_title = $articles->{$articlekey}->{subject};
}

print header,
	top({ conf => $conf,  article_title => $extra_title}),
	sidebar({ conf => $conf, articles => [ values %$articles ] });

if( $articlekey ) {
	my $art = $articles->{$articlekey};
	print article({ conf => $conf, article => $art });
} else {
	print articles({ conf => $conf, articles => [ values %$articles ] });
}

print bottom();

exit(0);

package Article;
use File::Basename;
use DateTime;
use Text::Markdown 'markdown';

sub new 
{
	my ($class, $args) = @_;

	if( ! -r $args->{filename} ) {
		die 'Unreadable file ' . $args->{filename};		
	}

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
	$self->{mtime} = $date->strftime('%a, %d  %b  %Y  %H:%M:%S  %z');

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

	my %articles = map { $_->{key} => $_ } map { $class->new({filename => $_}) } $find->in( $args->{data_dir});
	return \%articles;
}

sub formatted_body 
{
	my ($self) = @_;

	for ($self->{'content-type'}) {
		m{^text/plain$}  && do {
			return '<pre>' . $self->{body} . '</pre>';
		};
		m{^text/html$}  && do {
			return $self->{body};
		};
		m{^text/x-markdown$}  && do {
			return markdown($self->{body});
		};
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
    <title>[% article_title ? article_title : conf.title %]</title>
    <link rel="stylesheet" type="text/css" media="all" href="[% conf.url_base %]/blog.css" />
  </head>
  <body>
    <h1>[% article_title or conf.title %]</h1>
    <table border=0 cellspacing="0" cellpadding="0" width="100%">
    <tr>
     <td valign=top width="20%">
     <table border=1 cellspacing="0" cellpadding="10" width="100%">
     <tr><td>
[% END %]

[% BLOCK bottom %]
    </td>
    </tr>
    </table>
  </body>
</html>
[% END %]


[% BLOCK article %]
<table border=1 cellspacing="0" cellpadding="10" width="100%">
<tr><td>
  <table border=0 cellspacing="0" cellpadding="0" width="100%">
    <tr>
      <td><b><font color=purple size=+1>[% article.subject %]</font></b></td>
      <td align=right>[ link: <font color=lightgray><a href='[% conf.url_base %]/[% article.key %]'>[% article.key %]</a></font> | updated: [% article.mtime %] ]</td>
    </tr>
  </table>
</td></tr>
<tr><td>
	[% article.formatted_body ? article.formatted_body : article.body %]
</td></tr>
</table>
<br />
[% END %]

[% BLOCK articles %]
[% FOREACH article = articles %]
[% PROCESS article %]
[% END %]
[% END %]

[% BLOCK sidebar %]
<a href=/>dmo.ca</a> / <a href='/blog'>blog</a> <br><br>
[% FOREACH article = articles %]
[ <a href="[% conf.url_base %]/[% article.key %]">[% article.key %]</a> ]<br />[% article.subject %]<br>
<br>
[% END %]
</tr></td>
</table>
</td>
<td width=10>
</td>
<td valign=top>
[% END %]

[% BLOCK stylesheet %]
h1 { 	
	font-family: "Trebuchet MS", Geneva, Arial, Helvetica, SunSans-Regular, Verdana, sans-serif;
}
[% END %]
