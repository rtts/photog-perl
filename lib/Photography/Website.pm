package Photography::Website;
use strict;
use warnings;
use feature 'say';
use Image::Size           qw(imgsize);
use File::Path            qw(make_path);
use File::Basename        qw(basename dirname);
use File::ShareDir        qw(dist_file);
use File::Spec::Functions qw(catfile);
use Config::General       qw(ParseConfig);
use String::Random        qw(random_regex);
use Array::Utils          qw(array_minus);
use Image::ExifTool       qw(ImageInfo);
use Algorithm::Numerical::Shuffle qw(shuffle);
use Template; my $tt = Template->new({ABSOLUTE => 1});

our $silent = 0;
our $verbose = 0;
my $CONFIG_FILE = "photog.ini";

=head1 NAME

Photography::Website

=head1 SYNOPSIS

    use Photography::Website;

    my $source      = "$ENV{HOME}/Pictures";
    my $destination = "$ENV{HOME}/public_html";

    # Process the pictures tree
    my $website = Photography::Website::create_album($source);

    # Generate the website
    Photography::Website::generate($website);

=head1 DESCRIPTION

This Perl module generates a new or updates an existing photography
website. Please refer to the manual page of L<photog(3pm)|photog> for
documentation about the B<photog> command that provides a
user-friendly interface to use this module.

=head1 OPERATION

A photography website is generated in two stages. The first stage
processes the source directories to search for images and optional
C<photog.ini> files. This stage is kicked off by the
B<create_album>(I<$source_directory>) function, which recursively
builds the complete data structure and returns it. An example
structure is:

    {
      type => 'album'
      source => '/home/jj/Pictures',
      destination => '/home/jj/website',
      items => [
        {
          type => 'image',
          source => '/home/jj/Pictures/Sunset.jpg',
          destination => '/home/jj/website/Sunset.jpg',
          thumbnail => '/home/jj/website/thumbnails/Sunset.jpg',
        },
        {
          type => 'album',
          source => '/home/jj/Pictures/architecture',
          destination => '/home/jj/Pictures/architecture',
          items => [],
        },
      ],
    }

The second stage loops through this data structure and compares all
the sources with their destinations, and (re)generates them if
needed. It builds a complete website with nested albums of photographs
that mirrors the structure of the source image directory. This process
is started with the B<create>(I<$data_structure>) function.

=head1 FUNCTIONS

The rest of this manpage is a reference of all Photography::Website
module's functions.  These are divided into three categories:
1. functions that process the source files and directories,
2. functions that generate the website resource, and 3. helper
functions.

=head2 Source Processing Functions

=over

=item B<create_album>(I<$source>[, I<$parent>])

The main entry point for creating a website structure. $source should
be a directory name, $parent is only used when this function is called
recursively. Returns an album that with nested sub-albums that represents
the source directory tree.

=cut

sub create_album {
    my $source = shift;
    my $parent = shift; # optional
    my $album = configure($source, $parent) || return;
    for (list($source)) {
        my $item;
        if (-f) {
            $item = create_img($_, $album) || next;
        }
        elsif (-d) {
            $item = create_album($_, $album) || next;
        }
        push @{$album->{items}}, $item;
    }
    return $album;
}

=item B<create_img>(I<$source>, I<$parent>)

Tries to create an image node of the file referred to by $source. Also
requires a $parent that references an album node. It returns a false
value if no image was created, or a reference to an image hash.

=cut

sub create_img {
    my $source = shift;
    my $parent = shift;
    return if not is_image($source);
    my $img = {};
    my $filename = basename($source);
    $img->{type}        = 'image';
    $img->{name}        = strip_suffix($filename);
    $img->{url}         = $parent->{url} . $filename;
    $img->{href}        = $filename;
    $img->{src}         = "thumbnails/$filename";
    $img->{source}      = $source;
    $img->{destination} = catfile($parent->{destination}, $img->{url});
    $img->{thumbnail}   = catfile($parent->{destination}, $img->{src});
    $img->{watermark}   = $parent->{watermark};
    return $img;
}

=item B<configure>(I<$source>[, I<$parent>])

Configures a new album in various ways. First, it tries to get the
configuration from a file named C<photog.ini> in the album's $source
directory. Second, it tries to copy the configuration variables from
the $parent album. Finally, it supplies default values. Returns a
reference to a new album, without any items in the $album->{items}
array.

=cut

sub configure {
    my $source = shift;
    my $parent = shift; # optional
    my $album = get_config($source);

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

    # FIXED PARAMETERS
    # These cannot be changed from a config file.
    $album->{type}   = 'album';
    $album->{source} = $source;
    $album->{name}   = basename($source);
    $album->{root}   = $parent->{root} || $parent->{destination} || die
        "ERROR: Destination not specified";

    # SPECIAL PARAMETERS
    # Either set in the config file or calculated dynamically
    $album->{slug}        ||= basename($source);
    $album->{url}         ||= $parent->{url} ? "$parent->{url}$album->{slug}/": "/";
    $album->{href}        ||= $album->{slug} . '/';
    $album->{src}         ||= $album->{href} . "thumbnails/all.jpg";
    $album->{destination} ||= catfile($album->{root}, substr($album->{url}, 1));
    $album->{thumbnail}   ||= catfile($album->{destination}, "thumbnails/all.jpg");
    $album->{unlisted}    ||= ($album == $parent);

    # REGULAR PARAMETERS
    # Set in the config file, propagated from parent, or a default value.
    $album->{title}      ||= $parent->{title}      || "My Photography Website";
    $album->{copyright}  ||= $parent->{copyright}  || '';
    $album->{template}   ||= $parent->{template}   || dist_file('Photog', 'template.html');
    $album->{preview}    ||= $parent->{preview}    || 9;
    $album->{watermark}  ||= $parent->{watermark}  || '';
    $album->{sort}       ||= $parent->{sort}       || 'descending';
    $album->{fullscreen} ||= $parent->{fullscreen} || 1;
    $album->{oblivious}  ||= $parent->{oblivious}  || 0;

    return $album;
}

######################################################################

=back

=head2 Site Generation Functions

This section describes the functions that deal with (re)generating
files at the website destination.

=over

=item B<generate>(I<$album>[, I<$parent>])

=cut

sub generate {
    my $album = shift;
    my $parent = shift; # optional;
    my $update_needed = 0;

    for my $item (@{$album->{items}}) {
        if ($item->{type} eq 'image') {
            update_image($item) and $update_needed = 1;
            update_thumbnail($item) and $update_needed = 1;
        }
        if ($item->{type} eq 'album') {
            generate($item, $parent) and $update_needed = 1;
        }
    }
    update_preview($album, $parent) and $update_needed = 1;
    has_index($album) or $update_needed = 1;

    if ($update_needed) {
        update_index($album);
    }
}

sub update_image {
    my $img = shift;
    return if is_newer($img->{destination}, $img->{source});

    say $img->{url} unless $silent;
    make_path(dirname($img->{destination}));
    if ($img->{watermark}) {
        system('photog-watermark',
               $img->{source},
               $img->{watermark},
               $img->{destination},
           );
    }
    else {
        system('photog-scale',
               $img->{source},
               $img->{destination},
           );
    }
    return 1;
}


sub update_thumbnail {
    my $img = shift;
    return if is_newer($img->{thumbnail}, $img->{source});

    say $img->{thumbnail} unless $silent;
    make_path(dirname($img->{thumbnail}));
    system('photog-thumbnail',
           $img->{source},
           $img->{thumbnail},
       );
    return 1;
}

sub update_preview {
    my $album = shift;
    my $parent = shift; # optional
    return if $album->{unlisted};
    return if -f $album->{thumbnail};

    my @images = select_images($album, $parent);
    my $size = scalar @images;
    if ($size < 3) {
        die "ERROR: Not enough images in $album->{name} to create a preview (minimum is 3)";
    }
    elsif ($size < $album->{preview}) {
        $album->{preview} = $size;
        say "WARNING: Only $size preview images available for '$album->{name}'" unless $silent;
    }

    # Round the number of preview images down to 3, 6, or 9
    $album->{preview}-- until grep {$_ == $album->{preview}} (3, 6, 9);

    # Shuffle the list and pick N preview images
    @images = @{[shuffle @images]}[0..($album->{preview})-1];

    make_path(dirname($album->{thumbnail}));
    system('photog-preview',
           @images,
           $album->{thumbnail},
       );
    return 1;
}

sub update_index {
    my $album = shift;
    my $index = catfile($album->{destination}, "index.html");

    # Calculate the path to the static resources, relative
    # to the current page (relative pathnames ensure that
    # the website can be viewed by a browser locally)
    my $rel = $album->{url};
    $rel =~ s:[^/]+/:\.\./:g;
    $rel =~ s:^/::;
    $album->{static} = sub { "$rel$_[0]" };

    # Render index.html
    say "$album->{url}index.html" unless $silent;
    $tt->process($album->{template}, $album, $index)
        || die $tt->error();
}

sub select_images {
    my $album = shift;
    my $parent = shift; # optional

    my @images = grep { $_->{type} eq 'image' } @{$album->{items}};
    if ($parent) {
        my @parent_images = grep { $_->{type} eq 'image' } @{$parent->{items}};
        my %exclude = map {$_ => 1} map {$_->{href}} @parent_images;
        @images = grep {$exclude{$_->{href}}} @images;
    }
    @images = map {$_->{source}} @images;
    # End result: @images contains full paths to images whose filename does not
    # appear in the parent album

    return @images;
}


######################################################################

sub get_config {
    my $directory = shift;
    my $file = catfile($directory, $CONFIG_FILE);
    if (-f $file) {
        return { ParseConfig(-ConfigFile=>$file, -AutoTrue=>1) };
    }
    return 0;
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

sub list {
    my $dir = shift;
    my @files;
    my @dirs;
    opendir(my $dh, $dir) or die
        "ERROR: Cannot read contents of directory '$dir'\n";
    while (readdir $dh) {
        next if /^\./;
        push @files, "$dir/$_" if -f "$dir/$_";
        push @dirs, "$dir/$_" if -d "$dir/$_";
    }
    sub alphabetical { lc($a) cmp lc($b) }
    @files = sort alphabetical @files;
    @dirs = sort alphabetical @dirs;
    return @dirs, @files;
}

sub is_image {
    return shift =~ /\.jpg$/;
}

sub strip_suffix {
    my $file = shift;
    $file =~ s/\.[^\.]+$//;
    return $file;
}

sub is_newer {
    my $file1 = shift;
    my $file2 = shift;
    return unless -f $file1 and -f $file2;
    my $time1 = (stat $file1)[9];
    my $time2 = (stat $file2)[9];
    return $time1 > $time2;
}

sub has_index {
    my $album = shift;
    my $index = catfile($album->{destination}, "index.html");
    return -f $index;
}
1;
__END__

# Returns some EXIF data of an image in a hash reference
sub exif {
    my $file = shift or die;
    my $data = {};
    my $exif = ImageInfo($file, 'MakerNotes', 'Artist', 'Copyright', 'DateTimeOriginal', 'ExposureTime', 'FNumber', 'ISO', 'FocalLength');
    if (not %{$exif}) {
        die "EXIF info missing for $file, aborting...\n";
    }

    # Check for and manipulate MakerNote
    my $makerkey;
    for (keys %{$exif}) {
        if (/makernote/i) {
            $makerkey = $_;
            last;
        }
    }
    unless ($makerkey) {
        say "WARNING: MakerNote missing in EXIF data of $file" if $verbose;
        if ($manipulate_exif) {
            my $rawfile = $file;
            $rawfile =~ s|\.jpg$||;
            for my $ext ('dng', 'DNG', 'nef', 'NEF', 'cr2', 'CR2', 'crw', 'CRW') {
                if (-f "$rawfile.$ext") {
                    say "Copying EXIF info from $rawfile.$ext to $file" unless $silent;
                    system "exiftool -tagsfromfile \"$rawfile.$ext\" \"$file\" > /dev/null";
                    unlink $file . "_original";

                    # The original has been modified, so call process() again
                    # process $file;
                    last;
                }
            }
        }
    }
    else {
        say "MakerNote present in $file ($makerkey)" if $verbose;
    }

    # Check for and manipulate Artist
    unless ($exif->{Artist}) {
        say "WARNING: Artist missing in EXIF data of $file" if $verbose;
        if ($manipulate_exif) {
            my $choice = 0;
            if ($#artists) {
                do {
                    say "\nPlease choose between the following artists for $file:";
                    say $_+1 . ") $artists[$_]" for 0..$#artists;
                    $choice = (ask "Your choice:");
                } until ($choice =~ /\d+/ and $artists[$choice - 1]);
                $choice -= 1;
            }
            system "exiftool -m -artist=\"$artists[$choice]\" -copyright=\"$copyright\" \"$file\" > /dev/null";
            unlink $file . "_original";

            # The original has been modified, so call process() again
            # process $file;
        }
    }
    else {
        say "Artist \"$exif->{Artist}\" present in $file" if $verbose;
    }

    $data->{date} = $exif->{DateTimeOriginal} or 0;
    # $data->{settings} = "ISO $exif->{ISO}, $exif->{FocalLength}, f/$exif->{FNumber}, $exif->{ExposureTime}sec";
    my $artist = $exif->{Artist};
    return $data unless $artist;
    if ($artist =~ /Jaap Joris Vens/) {
        $artist = "Jaap Joris";
    }
    if ($artist =~ /Jolanda Verhoef/) {
        $artist = "Jolanda";
    }
    $data->{settings} = "<i>by $artist</i>";
    return $data;
}

# Extracts the date from a directory name in EXIF format
sub dirdate {
    my $dir = shift or die;
    my $name = name $dir;
    my $date;
    if ($name =~ /($date_regex)/) {
        $date = $1;
        $date =~ s/-/:/g;
        $date .= " 00:00:00";
    }
    else {
        # todo: Return the created date as a fallback
        $date = '0000:00:00 00:00:000';
    }
    return $date;
}

=head1 SEE ALSO

L<photog(3pm)|photog>

=head1 AUTHOR

Photography::Website was written by Jaap Joris Vens <jj@rtts.eu>, and is
used on his personal photography website http://www.superformosa.nl/

=cut


1;
