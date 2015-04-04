package Photography::Website::Configure;

=head1 NAME

Photography::Website::Configuration

=head1 SYNOPSIS

    use Photography::Website::Configuration
    my $album_config = Photography::Website::Configuration->new("source_directory")

=head1 DESCRIPTION

This module contains the configuration logic of Photog! the photography website generator. See photog(3) if you just want to use Photog!, and see Photography::Website for information about how it works. This mapage contains the list of all possible configuration variables and their defaults.

=head1 FUNCTIONS

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
    my $type   = shift;
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

=over 16

=item source

The source directory.

=cut

    $album->{source} = $source;

=item config

Path to the album's C<photog.ini>

=cut

    $album->{config} = catfile($source, $CONFIG_FILE);

=item name

Directory basename of the album, currently only used for debugging
purposes.

=cut

    $album->{name} = basename($source);

=item root

The destination directory of the root album. This is always inherited
from the parent album.

=cut

    $album->{root} = $parent->{root} || $parent->{destination} || die
        "ERROR: Destination not specified";

=back

=head3 Dynamic variables

=over 16

=item slug

Used as the basename for the destination directory, default: basename
of the source directory.

=cut

    $album->{slug} ||= basename($source);

=item url

Calculated by concatenating the parent url and the album slug.

=cut

    $album->{url} ||= $parent->{url}
        ? "$parent->{url}$album->{slug}/"
        : "/";

=item href

The album link for use inside the <a> tag in the template.

=cut

    $album->{href} ||= $album->{slug} . '/';

=item

The album preview image for use inside the <img> tag in the
template. Width and height will also be made available to the
template.

=cut

    $album->{src} ||= $album->{href} . "thumbnails/all.jpg";

=item destination

The album's destination directory. Calculated by concatenating the
root destination directory and the album's URL.

=cut

    $album->{destination} ||=
        catfile($album->{root}, substr($album->{url}, 1));

=item thumbnail

Path to the album preview image, for use a thumbnail in the parent
album. Defaults to the file "all.jpg" in subdirectory "thumbnails"
inside the destination directory.

=cut

    $album->{thumbnail} ||=
        catfile($album->{destination}, "thumbnails/all.jpg");

=item index

Path to to the album's C<index.html>.

=cut

    $album->{index} ||=
        catfile($album->{destination}, "index.html");

=item unlisted

Boolean value that specifies whether this album will be diplayed on
the parent album. Not inherited, always defaults to false (except for
the root album)

=cut

    $album->{unlisted} ||= ($album == $parent);

=item date

The album's ISO 8601 date, used for sorting albums and image
thumbnails. Default to the last modified time of the source directory.

=cut

    $album->{date} = DateTime->from_epoch(
        epoch => (stat $source)[9]);

=item

A list of filenames that will not be automatically deleted at the
album's destination directory. Defaults to an empty list, although the
root album will also get the directory 'static' appended to this list.

=cut

    $album->{protected} ||= ();

=back

=head3 Inherited variables

=over 16

=item title

The webpage title, default: "My Photography Website"

=cut

    if (not exists $album->{tittle}) {
        $album->{title} = $parent->{title}
            || "My Photography Website";
    }

=item copyright

Copyright notice, default: empty

=cut

    if (not exists $album->{copyright}) {
        $album->{copyright} = $parent->{copyright} || '';
    }

=item template

Path to the album's HTML template, default: Photog!'s
C<template.html>.

=cut

    $album->{template} ||= $parent->{template}
                       || dist_file('Photog', 'template.html');

=item preview

The number of images in the album's preview, default: 9.

=cut

    $album->{preview} ||= $parent->{preview} || 9;

=item watermark

Path to a (transparent!) watermark file, default: empty.

=cut

    if (not exists $album->{watermark}) {
        $album->{watermark} = $parent->{watermark} || '';
    }

=item sort

Either "ascending" or "descending", default: "descending".

=cut

    $album->{sort} ||= $parent->{sort} || 'descending';

=item fullscreen

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

=item oblivious

A boolean to indicate whether photog.ini files are required, default: false.

=cut

    if (not exists $album->{oblivious}) {
        $album->{oblivious} = $parent->{oblivious} || 0;
    }

=item scale_command

The command to resize an image to web scale, default: C<photog-scale>.

=cut

    $album->{scale-command} ||= $parent->{scale_command}
                            || 'photog-scale';

=item watermark_command

The command to watermark an image, default: C<photog-watermark>.

=cut

    $album->{watermark_command} ||= $parent->{watermark_command}
                                || 'photog-watermark';

=item thumbnail_command

The command to thumbnail an image, default: C<photog-thumbnail>.

=cut

    $album->{thumbnail_command} ||= $parent->{thumbnail_command}
                                || 'photog-thumbnail';

=item preview_command

The command to composite multiple images into a preview, default: C<photog-preview>.

=cut

    $album->{preview_command} ||= $parent->{preview_command}
                              || 'photog-preview';

### HALLELUJA!
    bless $album;
}

1;
