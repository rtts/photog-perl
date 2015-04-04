package Photography::Website::Configure

=over

=item B<configure>(I<$source>[, I<$parent>])

Configures a new album in various ways. First, it tries to get the
configuration from a file named C<photog.ini> in the album's $source
directory. Second, it tries to copy the configuration variables from
the $parent album. Finally, it supplies default configuration
values. Returns a reference to a new album, but one that doesn't have
any child nodes yet.

=cut

sub configure {
    my $source = shift;
    my $parent = shift; # optional
    my $album = get_config($source);
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

=pod

There are three types of configuration variables: Static variables,
Dynamic variables, and Inherited variables. The following sections
summarize their usage and default values. For a more detailed
explanation please refer to the photog(3) manual page.

=back

head3 Static variables

These cannot be changed from a config file.

=over 12

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

Either set in the config file or calculated dynamically.

=over 12

=item slug

Used as the basename for the destination directory, default: basename
of the source directory.

=cut

    if (not exists $album->{slug}) {
        $album->{slug} = basename($source);
    }

=item url

Calculated by concatenating the parent url and the album slug.

=cut

    if (not exists $album->{url}) {
        $album->{url} = $parent->{url} ? "$parent->{url}$album->{slug}/": "/";
    }

=item href

The album link for use inside the <a> tag in the template.

=cut

    if (not exists $album->{href}) {
        $album->{href} = $album->{slug} . '/';
    }

=item

The album preview image for use inside the <img> tag in the
template. Width and height will also be made available to the
template.

=cut

    if (not exists $album->{src}) {
        $album->{src} = $album->{href} . "thumbnails/all.jpg";
    }

=item destination

The album's destination directory. Calculated by concatenating the
root destination directory and the album's URL.

=cut

    if (not exists $album->{destination}) {
        $album->{destination} = catfile($album->{root}, substr($album->{url}, 1));
    }

=item thumbnail

Path to the album preview image, for use a thumbnail in the parent
album. Defaults to the file "all.jpg" in subdirectory "thumbnails"
inside the destination directory.

=cut

    if (not exists $album->{thumbnail}) {
        $album->{thumbnail} = catfile($album->{destination}, "thumbnails/all.jpg");
    }

=item index

Path to to the album's C<index.html>.

=cut

    if (not exists $album->{index}) {
        $album->{index} = catfile($album->{destination}, "index.html");
    }

=item unlisted

Boolean value that specifies whether this album will be diplayed on
the parent album. Default to true for all albums except the root
album.

=cut

    if (not exists $album->{unlisted}) {
        $album->{unlisted} = ($album == $parent);
    }

=item date

The album's ISO 8601 date, used for sorting albums and image
thumbnails. Default to the last modified time of the source directory.

=cut

    if (not exists $album->{date}) {
        $album->{date} = DateTime->from_epoch(epoch => (stat $source)[9]);
    }

=item

A list of filenames that will not be automatically deleted at the
album's destination directory. Defaults to an empty list, although the
root album will also get the directory 'static' appended to this list.

=cut

    if (not exists $album->{protected}) {
        $album->{protected} = ();
    }

=back

=head3 Inherited variables

Set in the config file, propagated from parent, or a default value.

=over 12

=item title

The webpage title, default: "My Photography Website"

=cut

    if (not exists $album->{title}) {
        $album->{title} = $parent->{title} || "My Photography Website";
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

    if (not exists $album->{template}) {
        $album->{template} = $parent->{template}
            || dist_file('Photog', 'template.html');
    }

=item preview

The number of images in the album's preview, default: 9.

=cut

    if (not exists $album->{preview}) {
        $album->{preview} = $parent->{preview} || 9;
    }

=item watermark

Path to a (transparent!) watermark file, default: empty.

=cut

    if (not exists $album->{watermark}) {
        $album->{watermark} = $parent->{watermark} || '';
    }

=item sort

Either "ascending" or "descending", default: "descending".

=cut

    if (not exists $album->{sort}) {
        $album->{sort} = $parent->{sort} || 'descending';
    }

=item



=cut

    if (not exists $album->{fullscreen}) {
        $album->{fullscreen} = $parent->{fullscreen} || 1;
    }

=item



=cut

    $album->{oblivious}
        ||= $parent->{oblivious}
        || 0;

=item



=cut

    $album->{scale_command}
        ||= $parent->{scale_command}
        || 'photog-scale';

=item



=cut

    $album->{watermark_command}
        ||= $parent->{watermark_command}
        || 'photog-watermark';

=item



=cut

    $album->{thumbnail_command}
        ||= $parent->{thumbnail_command}
        || 'photog-thumbnail';

=item



=cut

    $album->{preview_command}
        ||= $parent->{preview_command}
        || 'photog-preview';

    return $album;
}

1;
