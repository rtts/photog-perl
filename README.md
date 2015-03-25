## Photog!

Photog! turns a directory tree of source images into a photography
website with nested albums of chronologically sorted photographs. It
is created by [Jaap Joris Vens](http://rtts.eu/about/) who uses it for
[his personal photography website](http://www.superformosa.nl/).

##Installation instructions

First, make sure you have [ImageMagick](http://imagemagick.org/)
installed and that the `convert` command is available on the system PATH.
You can test this by running:

    $ convert --version
    Version: ImageMagick 6.8.9-9 Q16 x86_64 2015-01-05 http://www.imagemagick.org
    Copyright: Copyright (C) 1999-2014 ImageMagick Studio LLC

Now Photog! can be installed like any other Perl module. There's more
than one way to do it:

###Install as root

Download the latest release, then extract the files to a temporary
directory. From there, run the following commands:

    $ perl Makefile.PL
    $ make
    $ sudo make install

###Install as local user

To install Perl modules without root privileges, you need
[local::lib](http://search.cpan.org/perldoc?local::lib). Make sure
it's installed (e.g. `apt-get install liblocal-lib-perl` or `yum
install perl-local-lib`) and that you’ve appended the following line
to you `~/.bashrc`:

    eval "$(perl -Mlocal::lib)"

Now you can install the module by running the following commands:

    $ perl Makefile.PL
    $ make
    $ make install

###Install using Dist::Zilla

This module is maintained using [Dist::Zilla](http://dzil.org/), which
builds the module distributions and pushes them to the 'releases'
branch. Dist::Zilla can also be used for installing the module from
the original source code (which lives in the 'master' branch):

    $ git clone https://github.com/rtts/photog.git
    $ git checkout master
    $ dzil install

##Running Photog!

After installation, a manpage is available with the following command:

    man photog

To generate a photography website using default settings, simply `cd`
to your Pictures directory and execute `photog` with the destination
directory as its argument:

    cd ~/Pictures
    photog ~/public_html
