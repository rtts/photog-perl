Photog!
=======

Photog! turns a directory tree of source images into a photography
website with nested albums of chronologically sorted photographs. It
is created by [Jaap Joris Vens][1] who uses it for
[his personal photography website][2]. Photog also has
[its own website][3] with detailed installation instructions, online
manual pages, and nice fonts.

[1]: http://rtts.eu/about/
[2]: http://www.superformosa.nl/
[3]: http://photog.created.today/

Installation
------------

Photog! is written in Perl and packaged as a regular Perl module. The
stable branch of Photog!'s repository always contains the latest
release. Here are the installation instructions:

### Prerequisites

* **ImageMagick**: It's best to install this using your operating
  system package manager, e.g., `[apt-get|yum|dnf|brew|pacman|apt-cyg]
  install imagemagick`.

### Installation - the easy way

    $ cpan Photography::Website

This will fetch and build all dependencies and install Photog! to your
`$HOME/perl5` directory. To install Photog! system-wide, prepend
`sudo` to the above command. Instead of fetching from CPAN, t's also
possible to run `cpan .` inside the source directory.

### Installation - the old-fashioned way

    $ perl Makefile.PL
    $ make
    $ sudo make install

This works like you'd expect, but beware that you'll have to install
all the dependencies yourself.

### Installation - using Dist::Zilla

This module is maintained using Dist::Zilla, which builds the module
distributions and pushes them to the 'stable' branch. Dist::Zilla can
also be used for installing the module from the original source code
(which lives in the master branch).

    $ git clone https://github.com/rtts/photog.git
    $ git checkout master
    $ dzil install

Running Photog!
---------------

To generate a photography website using the default settings, simply
`cd` to your Pictures directory and execute `photog` with the
destination directory as its argument:

    cd ~/Pictures
    photog ~/public_html

That's it! Your website's main page should now be available in
`$HOME/public_html/index.html`. Go have a look!

Documentation
-------------

The documentation of Photog! is available after installation as a
collection of Unix-style manual pages. The available manpages are:

- `photog` -- An overview of the command-line interface and an
introduction to configuration and customization.

- `Photography::Website` -- Describes the interface and the inner
workings of the Photography::Website Perl module.

- `Photography::Website::Configure` -- A comprehensive list of all
configuration options and their default values.
