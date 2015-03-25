package Photography::Website;
use strict;
use warnings;
use constant false => 0;
use constant true  => 1;
use feature qw(say);
use File::Find;
use File::Basename;
use File::ShareDir qw(dist_dir);
use Image::Size;
use Cwd;
use Digest::MD5 qw(md5_hex);
use Image::ExifTool qw(:Public);
use Template; my $tt = Template->new({ABSOLUTE => 1});

die "Please install ImageMagick\n" unless `convert --version` =~ /ImageMagick/;

our @artists;
our $copyright;
our $manipulate_exif;
our $pictures;
our $website;
our $watermark;
our @ignore;
our $thumbnail_size;
our $image_size;
our $customize_thumbnails;
our $verbose;
our $silent;
our $share         = dist_dir 'Photog';
our $date_regex    = '[0-9]{4}-[0-9]{2}-[0-9]{2}';
our $private_regex = '(private)';
our $hidden_regex  = '(hidden)';
our $locked_regex  = '(locked)';

=head1 NAME

Photography::Website

=head1 SYNOPSIS

    use Photography::Website;

    my $conf = {

        # mandatory arguments
        Artist          => [ "Your Name", "Your Assistant's Name" ],
        Copyright       => "All Rights Reserved",
        Manipulate_EXIF => "true",
        Pictures        => "/home/username/Pictures",
        Website         => "/home/username/public_html",

        # optional arguments
        Watermark            => "/home/username/Pictures/watermark.png",
        Ignore               => [ "Lightroom Backups" ],
        Image_Size           => 2160,
        Customize_Thumbnails => "false",
        Verbose              => 1,
        Silent               => 0
    };

    Photography::Website::generate($conf);

=head1 DESCRIPTION

This Perl module generates a new or updates an existing photography
website. Please refer to the manual page of L<photog(3pm)|photog> for
documentation about the B<photog> command that provides a
user-friendly interface to use this module.

=head1 SEE ALSO

L<photog(3pm)|photog>

=head1 AUTHOR

Photography::Website was written by Jaap Joris Vens <jj@returntothesource.nl>, and
is used on his personal photography website http://www.superformosa.nl/

=cut

sub generate;
sub process;
sub create_gallery;
sub exif;
sub dirdate;
sub update_needed;
sub path;
sub is_image;
sub ignore;
sub title;
sub strip_dir;
sub name;
sub parent;
sub dirlist;
sub ask;
sub thumbnail;
sub scale;
sub scale_and_watermark;

# This is the main function. Call it with reference to a configuration
# hash and it will make you a pretty photography website!
sub generate {
    my $config = shift or die;

    # Die if the following arguments aren't present
    if (ref $config->{Artist} eq ref []) {
        @artists = @{$config->{Artist}} or die;
    }
    else {
        $artists[0] = $config->{Artist} or die;
    }
    $copyright = $config->{Copyright} or die;
    $manipulate_exif = $config->{Manipulate_EXIF} or die;
    $manipulate_exif = $manipulate_exif =~ /true/i;
    $pictures = $config->{Pictures} or die;
    $website = $config->{Website} or die;

    # These arguments are optional
    $watermark = $config->{Watermark};
    if (ref $config->{Ignore} eq ref []) {
        @ignore = @{$config->{Ignore}};
    }
    else {
        $ignore[0] = $config->{Ignore};
    }
    $thumbnail_size = $config->{Thumbnail_Size} || 366; # undocumented
    $image_size = $config->{Image_Size} || 2160;
    $customize_thumbnails = $config->{Customize_Thumbnails};
    $customize_thumbnails = $customize_thumbnails =~ /true/i;
    $verbose = $config->{Verbose};
    $silent = $config->{Silent};

    # Setup the website directory
    system "mkdir -p \"$website\"";
    system "cp -n --no-preserve=mode \"$_\" \"$website\"" for dirlist "$share/static";
    system "cp -n --no-preserve=mode \"$share/templates/index.template\" \"$website\"";

    # Call &process for each item below pictures tree
    say "Scanning $pictures..." unless $silent;
    finddepth { wanted => sub { process $_ },
              no_chdir => 1}, $pictures;
}

# Entry point for (re)generating individual web resources. Pass a
# filename or directory and the corresponding resource on the website
# will be updated if needed.
sub process {
    my $original = shift or die;
    return if ignore $original;
    my $derivative = $website . path $original;

    if (update_needed $original) {

        # If file
        if (-f $original) {
            say "$original => $derivative" unless $silent;
            thumbnail $original;
            exif $original;
            if ((parent $original) =~ /$private_regex/) {
                scale $original;
            }
            elsif (not $watermark) {
                scale $original;
            }
            elsif ((parent $original) !~ /$locked_regex/) {
                scale_and_watermark $original;
            }
        }

        # If directory
        elsif (-d $original) {
            thumbnail $original;
            my $index = $derivative . 'index.html';
            say "$original => $index" unless $silent;
            system "mkdir -p \"$derivative\"";

            # Calculate the relative path to the root
            my $root = path $original;
            $root =~ s:[^/]+/:\.\./:g;
            $root =~ s:^/::;

            # Write the index.html
            my $context = {
                    website_title => "$artists[0] Photography",
                    root => sub { "$root$_[0]" },
                    items => (create_gallery $original),
                    locked => ($original =~ /$locked_regex/) ? 1 : 0
                };
            $tt->process("$website/index.template", $context, $index) or die;
        }
    }
}

# Given an image directory, returns a reference to a list of hashes
# that represent gallery items, sorted by EXIF date
sub create_gallery {
    my $dir = shift or die;
    my @gallery;

    for my $original (dirlist $dir) {
        my $gallery_item = {};
        my $name = name $original;
        next if ignore $original;

        if (-f $original) {
            my $exifdata = exif $original;

            # Store image-specific info
            $gallery_item->{type}     = 'image';
            $gallery_item->{date}     = $exifdata->{date};
            $gallery_item->{settings} = $exifdata->{settings};
            $gallery_item->{src}      = "thumbnails/$name";
            $gallery_item->{href}     = $name;
        }
        elsif (-d $original) {
            next if ($name =~ /$private_regex/);
            next if ($name =~ /$hidden_regex/);

            # Store gallery-specific info
            $gallery_item->{type} = 'gallery';
            $gallery_item->{date} = dirdate $original;
            $gallery_item->{src}  = (strip_dir $name) . "/thumbnails/all.jpg";
            $gallery_item->{href} = (strip_dir $name) . '/';
        }

        my $absolute_src = $website . (path $dir) .  $gallery_item->{src};
        my ($width, $height) = imgsize $absolute_src;

        # Store remaining info
        $gallery_item->{width}  = $width;
        $gallery_item->{height} = $height;
        $gallery_item->{title}  = title $original;

        push @gallery, $gallery_item;
    }

    # Sort the list by EXIF date
    @gallery = sort {$b->{date} cmp $a->{date}} @gallery;

    return \@gallery;
}

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

# Returns true is the corresponding web resource is in need of an update
sub update_needed {
    my $original = shift or die;
    my $original_time;
    my $derivative = $website . path $original;
    my $derivative_time;
    my $template_time = 0;

    if (-f $original) {

        # Update needed if the image thumbnail is missing
        my $parent_dir = $derivative;
        $parent_dir =~ s|/[^/]+$||;
        return true unless -f "$parent_dir/thumbnails/" . name $original;
#        return false if $original =~ /$locked_regex/;

        $original_time = (stat $original)[9];
        $derivative_time = (stat $derivative)[9];
    }
    elsif (-d $original) {

        # New thumbnail needed if the gallery thumbnail is missing
        unless (-f $derivative . 'thumbnails/all.jpg') {
            unless ((path $original) eq '/') {
                thumbnail $original;
            }
        }

        my $index = $derivative . 'index.html';
        my $latest = (`ls "$original" -t1`)[0]; # todo: don't fork
        chomp $latest;
        $original_time = (stat "$original/$latest")[9];
        $derivative_time = (stat $index)[9];
        $template_time = (stat "$website/index.template")[9];
    }

    unless ($derivative_time) {
        return true;
    }
    else {
        return ($original_time > $derivative_time) || ($template_time > $derivative_time);
    }
}

# Given an absolute path beneath the $pictures folder, returns the URL
# of the corresponding resource (which can be either an image or a
# gallery URL)
sub path {
    my $dir = shift or die;
    my $path = '/';

    # Loop over all parent dirs until $pictures
    for (split '/', substr "$dir", length $pictures) {
        next unless $_;

        # Keep image filenames intact
        if (is_image $_) {
            $path .= "$_";
        }

        # Substitute private dirs with secret URL
        elsif (/$private_regex/) {
            $path .= md5_hex("$_\n") . '/';
        }

        # Remove date and anything after a space
        else {
            s/$date_regex //;
            s/ .*//;
            $path .= "$_/";
        }
    }
    return $path;
}

sub is_image {
    return shift =~ /\.jpg$/;
}

# Returns true in the following circumstances:
# - the argument matches an entry from the @ignore list
# - the argument is a non-image file
# - the argument is a directory with less than 3 images
sub ignore {
    my $candidate = shift or die;
    if (grep {$candidate =~ /$_/} @ignore) {
        return true;
    }
    if (-f $candidate) {
        return not is_image $candidate;;
    }
    elsif (-d $candidate) {
        my @listing = grep {is_image $_} dirlist $candidate;
        return scalar @listing < 3;
    }
}

# Returns the display name of a file
sub title {
    my $file = name shift or die;
    $file =~ s/\.[^\.]+$//;
    return $file;
}

# Returns the target directory name
sub strip_dir {
    my $dir = name shift or die;
    $dir =~ s/$date_regex //;
    $dir =~ s/ .*//;
    return $dir;
}

# Returns only the name of a file
sub name {
    my $file = shift or die;
    return (split m:/:, $file)[-1];
}

# Returns only the parent directory of a file
sub parent {
    my $file = shift or die;
    return (split m:/:, $file)[-2];
}

# Return a list of files in the directory
sub dirlist {
    my $dir = shift or die;
    $dir =~ s/\/$//;
    my @list;
    opendir my $dh, $dir or die;
    while (readdir $dh) {
        next if /^\./;
        push @list, "$dir/$_";
    }
    return @list;
}

sub ask {
    my $question = shift;
    print "$question ";
    my $answer = <STDIN>;
    chomp $answer;
    print "\n";
    return $answer;
}

# Creates a thumbnail image of an original image or directory
sub thumbnail {
    my $original = shift or die;
    my $path = path $original;
    my $name = name $original;
    my $output;
    if (-f $original) {

        # Calculate thumbnail path
        my $escaped_name = quotemeta $name;
        $output = $website . $path;
        $output =~ s|$escaped_name|thumbnails/|;
        `mkdir -p "$output"`;
        $output .= $name;

        # Todo: use Perlmagick API
        system("convert \"$original\" \\
                    -resize '5000x$thumbnail_size' \\
                    -unsharp 1.5x+0.7+0.02 \\
                    -quality 88% \"$output\"") and die;
    }
    elsif (-d $original) {
        my $previews;
        $output = $website . $path . 'thumbnails/all.jpg';

        # Don't create a thumbnail for the homepage
        return if $path eq '/';

        # Don't create a thumbnail if one already exists
        return if -f $output;

        # Don't create a thumbnail if there's less than 3 images
        my $files = grep {is_image $_ } dirlist $original;
        return if $files < 3;
        my @options = (3,6,9);
        pop @options if $files < 9;
        pop @options if $files < 6;

        if ($customize_thumbnails) {
            do {
                say "\nCustomizing thumbnail for \"$name\" ($files images)";
                $previews = ask "Please choose the number of images to include (3, 6, or 9)";
            } until (grep {$previews == $_} @options);
        }
        else {
            $previews = $options[-1];
        }

        # IF IT'S STUPID AND IT WORKS, IT AIN'T STUPID!
        my @images = `ls -1 '$original' | grep '\.jpg\$' | sort --random-sort | head -$previews`;
        chomp @images;
        my $b = 8;
        chdir $website . (path $original) . 'thumbnails';
        if ($previews == 3) {
            system("convert -bordercolor black xc:red \\
                \\( '$images[0]' -border $b -resize 200x1000 \\) \\
                \\( '$images[1]' -border $b -resize 200x1000 \\) \\
                \\( '$images[2]' -border $b -resize 200x1000 \\) \\
                -append -crop +0+1 -shave 2 +repage all.jpg") and die;
        }
        elsif ($previews == 6) {
            system("convert -bordercolor black xc:red \\
                \\( \\( '$images[0]' -border $b \\) \\
                    \\( '$images[1]' -border $b \\) +append -resize 400x1000 \\) \\
                \\( \\( '$images[2]' -border $b \\) \\
                    \\( '$images[3]' -border $b \\) +append -resize 400x1000 \\) \\
                \\( \\( '$images[4]' -border $b \\) \\
                    \\( '$images[5]' -border $b \\) +append -resize 400x1000 \\) \\
                -append -crop +0+1 -shave 2 +repage all.jpg") and die;
        }
        elsif ($previews == 9) {
            system("convert -bordercolor black xc:red \\
                \\( \\( '$images[0]' -border $b \\) \\
                    \\( '$images[1]' -border $b \\) \\
                    \\( '$images[2]' -border $b \\) +append -resize 600x1000 \\) \\
                \\( \\( '$images[3]' -border $b \\) \\
                    \\( '$images[4]' -border $b \\) \\
                    \\( '$images[5]' -border $b \\) +append -resize 600x1000 \\) \\
                \\( \\( '$images[6]' -border $b \\) \\
                    \\( '$images[7]' -border $b \\) \\
                    \\( '$images[8]' -border $b \\) +append -resize 600x1000 \\) \\
                -append -crop +0+1 -shave 2 +repage all.jpg") and die;
        }

        # Remove the index.html of the parent dir, because it needs to
        # be regenerated with the new gallery thumbnail dimensions
        my $rm = "$website$path";
        $rm =~ s|/[^/]+/$||;
        unlink "$rm/index.html";
    }
}

sub scale {
    my $original = shift or die;
    my $output = $website . path $original;
    system("convert \"$original\" \\
        -resize 10000x$image_size miff:- |\\
        convert -quality 88% - \"$output\"") and die;
}

sub scale_and_watermark {
    my $original = shift or die;
    my $output = $website . path $original;
    die unless $watermark;
    system("convert \"$original\" \\
        -resize 10000x$image_size miff:- |\\
        composite -gravity southeast \"$watermark\" - miff:- |\\
        convert -quality 88% - \"$output\"") and die;
}

1;
