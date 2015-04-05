package Photography::Website::Configuration;
use warnings;
use strict;

use DateTime;
use File::Basename        qw(basename dirname);
use File::ShareDir        qw(dist_file dist_dir);
use File::Spec::Functions qw(catfile);
use Config::General       qw(ParseConfig);
use String::Random        qw(random_regex);

# use Class::Tiny qw(source configfile name root slug url href src destination thumbnail index unlisted date protected title copyright template preview watermark sort fullscreen oblivious scale_command watermark_command thumbnail_command preview_command);

my $CONFIG_FILE = "photog.ini";

=head1 NAME

Photography::Website::Configuration

=head1 DESCRIPTION

This module contains the configuration logic of Photog! the
photography website generator. See photog(3) if you just want to use
Photog!, and see Photography::Website(1) for information about how it
works. This manpage contains the list of all possible configuration
variables and their defaults.

=head1 FUNCTIONS

This module has one main function:

=over

=item B<new>(I<$source>[, I<$parent>])

Configures a new album in various ways. First, it tries to get the
configuration from a file named C<photog.ini> in the album's $source
directory. Second, it tries to copy the configuration variables from
the $parent album. Finally, it supplies default configuration
values. It returns a reference to a new album, but one that doesn't
have any child nodes yet.

=cut

sub new {
    my $source = shift;
    my $parent = shift; # optional
    my $album  = get_config($source);
    $album->{type} = 'album';

    # Special case for root albums
    $parent = $album if not $parent;

    # Implementation of the "oblivious" feature
    if (not $album) {
        return if $parent->{oblivious};
        $album = {};
    }

    # Implementation of the "private" feature
    if ($album->{private}) {
        $album->{slug} = random_regex('[1-9][a-hjkp-z2-9]{15}');
        $album->{unlisted} = "true";
        delete $album->{private};
        save_config($album, $source);
    }

=back

=head1 CONFIGURATION VARIABLES

There are three types of configuration variables: static variables,
dynamic variables, and inherited variables. Static variables cannot be
changed from a configuration file. Dynamic variables can be set in a
configuration or they are calculated dynamically. Inherited variables
are either set from a configuration file, inherited from the parent,
or a default value.

=head3 Static variables

=over 18

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

    $album->{root} = $parent->{root} || $parent->{destination} || die
        "ERROR: Destination not specified";

=back

=head3 Dynamic variables

=over 18

=item B<slug>

Used as the basename for the destination directory, default: basename
of the source directory.

=cut

    $album->{slug} ||= basename($source);

=item B<url>

Calculated by concatenating the parent url and the album slug.

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
root destination directory and the album's URL.

=cut

    $album->{destination} ||=
        catfile($album->{root}, substr($album->{url}, 1));

=item B<thumbnail>

Path to the album preview image, for use a thumbnail in the parent
album. Defaults to the file "all.jpg" in subdirectory "thumbnails"
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
the parent album. Not inherited, always defaults to false (except for
the root album)

=cut

    $album->{unlisted} ||= ($album == $parent);

=item B<date>

The album's ISO 8601 date, used for sorting albums and image
thumbnails. Default to the last modified time of the source directory.

=cut

    $album->{date} = DateTime->from_epoch(
        epoch => (stat $source)[9]);

=item B<protected>

A list of filenames that will not be automatically deleted at the
album's destination directory. Defaults to ('index.html', 'thumbnails'). The
root album will also get the directory 'static' appended to this list.

=cut

    $album->{protected} ||= ['index.html', 'thumbnails'];

=back

=head3 Inherited variables

=over 18

=item B<title>

The webpage title, default: "My Photography Website"

=cut

    if (not exists $album->{tittle}) {
        $album->{title} = $parent->{title}
            || "My Photography Website";
    }

=item B<copyright>

Copyright notice, default: empty

=cut

    if (not exists $album->{copyright}) {
        $album->{copyright} = $parent->{copyright} || '';
    }

=item B<template>

Path to the album's HTML template, default: Photog!'s
C<template.html>.

=cut

    $album->{template} ||= $parent->{template}
                       || dist_file('Photog', 'template.html');

=item B<preview>

The number of images in the album's preview, default: 9.

=cut

    $album->{preview} ||= $parent->{preview} || 9;

=item B<watermark>

Path to a (transparent!) watermark file, default: empty.

=cut

    if (not exists $album->{watermark}) {
        $album->{watermark} = $parent->{watermark} || '';
    }

=item B<sort>

Either "ascending" or "descending", default: "descending".

=cut

    $album->{sort} ||= $parent->{sort} || 'descending';

=item B<fullscreen>

A boolean to indicate whether large images should be made available, default: true.

=cut

    if (not exists $album->{fullscreen}) {
        if (not defined $parent->{fullscreen}) {
            $album->{fullscreen} = 1;
        }
        else {
            $album->{fullscreen} = $parent->{fullscreen};
        }
    }

=item B<oblivious>

A boolean to indicate whether photog.ini files are required, default: false.

=cut

    if (not exists $album->{oblivious}) {
        $album->{oblivious} = $parent->{oblivious} || 0;
    }

=item B<scale_command>

The command to resize an image to web scale, default: C<photog-scale>.

=cut

    $album->{scale_command} ||= $parent->{scale_command}
                            || 'photog-scale';

=item B<watermark_command>

The command to watermark an image, default: C<photog-watermark>.

=cut

    $album->{watermark_command} ||= $parent->{watermark_command}
                                || 'photog-watermark';

=item B<thumbnail_command>

The command to thumbnail an image, default: C<photog-thumbnail>.

=cut

    $album->{thumbnail_command} ||= $parent->{thumbnail_command}
                                || 'photog-thumbnail';

=item B<preview_command>

The command to composite multiple images into a preview, default: C<photog-preview>.

=cut

    $album->{preview_command} ||= $parent->{preview_command}
                              || 'photog-preview';

=back

=cut

    return $album;
}

=head1 ADDITIONAL FUNCTIONS

The new() function calls two additional helper functions:

=over

=item B<get_config>(I<$directory>)

Tries to find and parse $directory/photog.ini into a configuration
hash and returns a reference to it. Returns false if no photog.ini was
found.

=cut

sub get_config {
    my $directory = shift;
    my $file = catfile($directory, $CONFIG_FILE);
    if (-f $file) {
        return { ParseConfig(-ConfigFile=>$file, -AutoTrue=>1) };
    }
    return 0;
}

=item B<save_config>(I<$config>, I<$directory>)

The other way around, saves the $config hash reference to the file
photog.ini inside $directory. Returns nothing.

=cut

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

=back

=head1 SEE ALSO

photog(3), Photography::Website(1)

=head1 AUTHOR

Photog! was written by Jaap Joris Vens <jj@rtts.eu>, and is used to
create his personal photography website at http://www.superformosa.nl/

=cut

1;
