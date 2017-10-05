# navaid.com support code
This is the code I use to generate the databases that I use on my navaid.com
site. I've had most of this for nearly 20 years and so it's a mish-mash of
various coding styles, obsolete code, code that is good enough to get the job
done and there's no point replacing it with something better, and stuff I'm
still maintaining and using. I'm putting it on a public github account because
employers want to see code you've written, and frankly I spend 90% of my spare
time training for kayak racing instead of coding these days so I don't have
much to show, and almost everything I've written during work time belongs to
other people who won't let me share it.

I'm releasing this to the public domain. If you can make sense of it and find
something you can use, go ahead and use it.

## "Support" code
I generate the databases on my personal Linux box, not on the linode that runs
the navaid.com site. That's because my personal Linux box is faster than the
linode and has more RAM. Also because loading the EAD xml file takes hours and
hours and I don't want navaid.com to be unusable for that time.

So I generate it at home, do a tiny bit of validation that the new file loaded
correctly, then dump the database (using the program "postGISDump" that you
might see somewhere here) and scp it up to navaid.com and load it there.

These days, the only programs I use are "check_diffs" before and after
loading, loadFAA.pl for loading FAA data and loadEAD.pl for loading EAD data
(until they stop providing updates), and postGISDump. The load scripts use two
C programs, pntInPoly and magvar to calculate if a point is in a particular
Canadian province and calculating the magnetic variance respectively. They
also use web calls to get state and country codes from the GeoNames server,
which is rate limited so I try to remember what it told me and not use it for
known points.
