my $DIST = 'Photography-Website';
package Photography::Website::Configure;

use warnings;
use strict;

use DateTime;
use File::Basename        qw(basename dirname);
use File::ShareDir        qw(dist_file);
use File::Spec::Functions qw(catfile);
use Config::General       qw(ParseConfig);
use String::Random        qw(random_regex);

my $CONFIG_FILE = "photog.ini";

=head1 NAME

Photography::Website::Configure - List of Configuration Options

=head1 DESCRIPTION

This module contains the configuration logic of Photog! the
photography website generator. See L<photog> for the documentation
about the command-line interface and see L<Photography::Website> for
documentation about the Perl interface.

What follows is a comprehensive list of all configuration options
currently in use, with a short description of their usage and their
default value.

=head2 Image variables

=over 12

=cut

sub image {
    my $source = shift;
    my $parent = shift;
    return if not is_image($source);
    my $img = {
        type   => 'image',
        parent => $parent,
    };
    my $filename = basename($source);

=item B<name>

The image filename without the extension. Is used by the default
template as the caption when the image is viewed fullscreen.

=cut

    $img->{name}   = strip_suffix($filename);

=item B<url>

The absolute URL of the fullscreen image. This is used to calculate
the image destination. Templates should use the relative URL (see next).

=cut

    $img->{url}    = $parent->{url} . $filename;

=item B<href>

The relative URL of the full-size image, i.e., the image filename.

=cut

    $img->{href}   = $filename;

=item B<src>

The relative URL of the image thumbnail, i.e., C<thumbnails/$filename>.

=cut

    $img->{src}    = "thumbnails/$filename";

=item B<source>

The full path to the original image in the source directory.

=cut

    $img->{source} = $source;

=item B<destination>

The full path to the fullscreen image in the destination directory.

=cut

    $img->{destination} = catfile($parent->{root}, substr($img->{url}, 1));

=item B<thumbnail>

The path to the image thumbnail.

=cut

    $img->{thumbnail} = catfile($parent->{destination}, $img->{src});


    # These are documented further below
    $img->{watermark}         = $parent->{watermark};
    $img->{scale_command}     = $parent->{scale_command};
    $img->{watermark_command} = $parent->{watermark_command};
    $img->{thumbnail_command} = $parent->{thumbnail_command};
    return $img;
}

=back

=head2 Album variables

There are three types of album configuration variables: static variables,
dynamic variables, and inherited variables. Static variables cannot be
changed from a configuration file. Dynamic variables can be set in a
configuration or they are calculated dynamically. Inherited variables
are either set from a configuration file, inherited from the parent,
or a default value.

=over 12

=cut

sub album {
    my $source = shift;
    my $parent = shift; # optional
    my $album  = get_config($source);

    # Special case for root albums
    # $parent = $album if not $parent;

    # Implementation of the "oblivious" feature
    if (not $album) {
        return if $parent->{oblivious};
        $album = {};
    }

    # Implementation of the "private" feature
    if (defined $album->{slug} and $album->{slug} eq 'private') {
        $album->{slug} = random_regex('[1-9][a-hjkp-z2-9]{15}');
        $album->{unlisted} = "true";
        save_config($album, $source);
    }

    $album->{type} = 'album';
    $album->{parent} = $parent;

    # Instantiate the global allfiles hash
    if (not $parent) {
        $album->{allfiles} = {};
    }
    else {
        $album->{allfiles} = $parent->{allfiles};
    }


=item I<Static variables>

=item B<source>

The source directory.

=cut

    $album->{source} = $source;

=item B<config>

Path to the album's C<photog.ini>

=cut

    $album->{config} = catfile($source, $CONFIG_FILE);

=item B<name>

Directory basename of the album, currently only used for debugging
purposes.

=cut

    $album->{name} = basename($source);

=item B<root>

The destination directory of the root album. This is always inherited
from the parent album.

=cut

    if ($parent) {
        $album->{root} = $parent->{root};
    }
    else {
        $album->{root} = $album->{destination} || die
            "ERROR: Destination not specified";
    }

=item I<Dynamic variables>

=item B<slug>

A slug is the part of the URL that identifies an album,
e.g. C<www.example.com/slug/>. The default value is the directory's
name, so be careful not to use characters in directory names that are
not allowed in URLs, like spaces. Or, simply override this value to
choose an appropriate URL for each album.

The special value of "private" will cause a random slug to be
generated consisting of 16 alphanumeric characters, which will
immediately be saved to the C<photog.ini> file, replacing the
original "private" value. In addition, the variable B<unlisted>
will be set to true. Use this for creating private albums that
are only accessible to people who know the secret URL.

=cut

    $album->{slug} ||= basename($source);

=item B<url>

Calculated by concatenating the parent url and the album slug.
Overriding this option allows the source directories to be differently
organized than the destination directories.

=cut

    $album->{url} ||= $parent->{url}
        ? "$parent->{url}$album->{slug}/"
        : "/";

=item B<href>

The album link for use inside the <a> tag in the template.

=cut

    $album->{href} ||= $album->{slug} . '/';

=item B<src>

The album preview image for use inside the <img> tag in the
template. Width and height will also be made available to the
template.

=cut

    $album->{src} ||= $album->{href} . "thumbnails/all.jpg";

=item B<destination>

The album's destination directory. Calculated by concatenating the
root destination directory and the album's URL. Although possible,
overriding this option for subdirectories is not recommended. Use the
B<url> option instead (see above).

=cut

    $album->{destination} ||=
        catfile($album->{root}, substr($album->{url}, 1));

=item B<thumbnail>

Path to the album preview image, for use a thumbnail in the parent
album. Defaults to the file C<all.jpg> in subdirectory C<thumbnails>
inside the destination directory.

=cut

    $album->{thumbnail} ||=
        catfile($album->{destination}, "thumbnails/all.jpg");

=item B<index>

Path to to the album's C<index.html>.

=cut

    $album->{index} ||=
        catfile($album->{destination}, "index.html");

=item B<unlisted>

Boolean value that specifies whether this album will be diplayed on
the parent album. The album page remains accessible to people who know
the URL. Defaults to C<false>.  Not inherited, always defaults to
false (except for the root album)

=cut

    $album->{unlisted} ||= (not defined $album->{parent});

=item B<date>

The ISO 8601 date and optionally time of this album. This is used when
sorting items chronologically. The default is the directory's
modification date. The default template never actually shows dates,
but it can also be used to determine the placement of album previews
on a page.

=cut

    $album->{date} ||= DateTime->from_epoch(
        epoch => (stat $source)[9]);

=item B<protected>

A list of filenames that will not be automatically deleted at the
album's destination directory. Defaults to ('index.html',
'thumbnails'). The root album will also get the directory 'static'
appended to this list.

=cut

    if (not exists $album->{protected}) {
        $album->{protected} = [];
    }
    push @{$album->{protected}}, ('index.html', 'thumbnails');

=item I<Inherited variables>

=item B<title>

In the default template, the title appears at the top of the page. The
default value is "My Photography Website". Please set this to
something more catchy. You can also override it for specific albums to
show an album name.

=cut

    if (not exists $album->{title}) {
        $album->{title} = $parent->{title}
            || "My Photography Website";
    }

=item B<copyright>

In the default template, the copyright notice appears at the
bottom of the page. The default value is empty.

=cut

    if (not exists $album->{copyright}) {
        $album->{copyright} = $parent->{copyright} || '';
    }

=item B<template>

Path to an HTML file containing directives in L<Template::Toolkit>
syntax. The current album will be made available as the variable
"album", from where all additional configuration variables can be
accessed using dot syntax, i.e., album.title, album.copyright etc. You
can even make up your own configuration variables in C<photog.ini> and
have them available in the template. The default is the file
C<template.html> that's included with Photog!. Use it as a starting
point to create your own template!

=cut

    $album->{template} ||= $parent->{template}
                       || dist_file($DIST, 'template.html');

=item B<preview>

An album preview is a thumbnail image of the album that contains a
number of smaller images. This option sets the number of preview
images for an album. Allowed values are 3, 6, and 9. The default is 9.

=cut

    $album->{preview} ||= $parent->{preview} || 9;

=item B<watermark>

The path to a transparent PNG file that will be used to watermark all
fullscreen images in an album. The command C<photog-watermark> is
called to do the actual watermarking, and it currently places the
watermark in the lower right corner. The default is to not watermark
website images.

=cut

    if (not exists $album->{watermark}) {
        $album->{watermark} = $parent->{watermark} || '';
    }

=item B<sort>

Photos are sorted according to EXIF date. Possible sort orders are:
C<ascending>, C<descending>, or C<random>. The default value is
C<descending>.

=cut

    $album->{sort} ||= $parent->{sort} || 'descending';

=item B<fullscreen>

A boolean to indicate whether large images should be made
available. Use this to prevent access to full-size images by clients
who haven't paid yet. Defaults to true.

=cut

    if (not exists $album->{fullscreen}) {
        if ($album->{parent}) {
            $album->{fullscreen} = $parent->{fullscreen};
        }
        else {
            $album->{fullscreen} = 1;
        }
    }

=item B<oblivious>

A boolean value that specifies whether C<photog.ini>
files are required. If true, Photog! will only consider a
subdirectory an album when it contains a C<photog.ini> file, even if
the file is empty. Defaults to false.

=cut

    if (not exists $album->{oblivious}) {
        $album->{oblivious} = $parent->{oblivious} || 0;
    }

=item B<scale_command>

The path to a command to convert an original image to a fullscreen
web-image. The command will receive 2 arguments: The source image path
and the destination image path. The default is C<photog-scale>, which
will scale an image to measure 2160 pixels vertically.

=cut

    $album->{scale_command} ||= $parent->{scale_command}
                            || 'photog-scale';

=item B<watermark_command>

The command that does the image watermarking. The command will receive
3 arguments: Paths to the source image, the watermark image, and the
destination image. The default command is C<photog-watermark> which
places the watermark file in the lower-right corner.

=cut

    $album->{watermark_command} ||= $parent->{watermark_command}
                                || 'photog-watermark';

=item B<thumbnail_command>

The path to a command that generates image thumbnails. The command
receives 2 arguments: The source image path and the thumbnail
destination path. The default is C<photog-thumbnail>, which performs
quite a bit of sharpening to make sure that the thumbnail doesn't
become blurry after resizing.

=cut

    $album->{thumbnail_command} ||= $parent->{thumbnail_command}
                                || 'photog-thumbnail';

=item B<preview_command>

The command that generates album previews by compositing multiple
thumbnails together. It will receive paths to the source images'
thumbnails as its arguments, and the path to a destination file as its
final argument. Currently, Photog! will only request previews of 3, 6,
or 9 images.

=cut

    $album->{preview_command} ||= $parent->{preview_command}
                              || 'photog-preview';

=back

=cut

    # Finally, inherit all remaining parent values
    for (keys %$parent) {
        next if $_ eq 'items';
        next if exists $album->{$_};
        $album->{$_} = $parent->{$_};
    }

    return $album;
}

sub get_config {
    my $directory = shift;
    my $file = catfile($directory, $CONFIG_FILE);
    if (-f $file) {
        return { ParseConfig(-ConfigFile=>$file, -AutoTrue=>1) };
    }
    else {
        return 0;
    }
}

sub save_config {
    my $config = shift;
    my $directory = shift;
    my $file = catfile($directory ,$CONFIG_FILE);
    open(my $fh, '>', $file)
        or die "ERROR: Can't open '$file' for writing\n";
    for my $key (keys %{$config}) {
        say $fh "$key = $config->{$key}";
    }
}

sub is_image {
    my $name = lc(shift);
    return 1 if $name =~ /\.jpg$/;
    return 1 if $name =~ /\.jpeg$/;
    return 0;
}

sub strip_suffix {
    my $file = shift;
    $file =~ s/\.[^\.]+$//;
    return $file;
}

=head1 SEE ALSO

L<photog>, L<Photography::Website>

=head1 AUTHOR

Photog! was written by Jaap Joris Vens <jj@rtts.eu>, and is used to
create his personal photography website at L<http://www.superformosa.nl/>

=cut

1;
