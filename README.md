# sfmb - Single File Markdown Blog

This is a quick and dirty blog script, written with the following requirements:

   1. One file
   1. Posting via text files with minimal markup

It is likely not suitable for high-traffic implementations, as it runs as a
Perl CGI.  It is also not suitable if you want commenting, web-based posting,
etc.  In fact, it's probably not suitable for much, which is why I no longer
use it, but YMMV.

## Usage

Clone the repository.  Then:

  cp _blog ~/.blog
  cp blog.pl /var/www/some/cgi/directory

and you're deployed.

Of course, it will have no posts and look ugly as sin, as the defaults are
horrible and likely point to the wrong paths.  So....

    mkdir ~/.blog/entries
    ~/.blog/blog_new

and compose an entry in your editor.

Then:

    $EDITOR /var/www/some/cgi/directory/blog.pl

and modify the `$conf` section appropriately.  You will at minimum want to
point data_dir to your $HOME/.blog/entries.

Now would also be a good time to adjust templates, CSS, etc, at the bottom of
blog.pl


## Formatting

Basically, blog entries are formatted like an email message. You have
a header section, in the format of

Name: value

followed by a blank line, and then the body of the message.

### Headers

#### Subject:

A blog entry should have, at minimum, a Subject: header.  This will be
used as the title of your blog post.

Other headers are optional, and include:

#### Content-Type:

This is the MIME type of your article.  Your choices at this point are:
	text/plain
	text/html
	text/x-markdown

text/plain is rendered as-is, as plain text.
text/html is expected to contain HTML.

text/x-markdown is formatted in the simple markup language
[Markdown](http://daringfireball.net/projects/markdown/).

If no Content-Type header is present, we will try to autodetect it.  If
the body begins with a < character, we assume text/html, otherwise we
assume text/plain.

#### Alias:

This provides a value for a permanent link.  If not present, the filename of
the article will be used.

An example:

        Alias: bad-day-at-the-office

will have a permalink of

	http://www.yourdomain.tld/blog/bad-day-at-the-office

instead of

	http://www.yourdomain.tld/blog/20060630074132

#### Tags:

A comma-separated list of tag keywords. 

An example:

	Tags: vim, perl, blog

Tags will be rendered as a tagcloud in the sidebar, as well as linkable from
each article to a list of articles with that tag.  They are optional.

### Inline options

#### <read more>

Inserting a <read more> tag inside the body of your post will let blog.pl
display only the text up to that point on the index page, followed by a 'read
more' link to the full article.

This should work for all content-type: options.


## Future Features

These features have been requested, but are not yet implemented.  Patches welcome.

   1. A configuration file.  Probably in YAML or JSON.
   1. Previous/next article arrows
   1. Better navigation of old content, incl. sidebar listing year/month historical entries.
   1. External templates and CSS, rather than using inline.

