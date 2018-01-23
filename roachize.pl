#!/usr/bin/env perl
use strict;
use Getopt::Long 'HelpMessage', qw(:config bundling);

GetOptions ('source=s'  => \my $sourceDumpFile,
            'dest=s'    => \my $destDumpFile,
            'omitdata'  => \my $omitData,
            '2'  => \my $v2,
            'help'     =>   sub { HelpMessage(0) },
) or HelpMessage(1);

HelpMessage(1) unless $sourceDumpFile && $destDumpFile;

my $haveDumpedFKIndicies = 0;
my %pk;
my %pkc;
my @fk;

# First find the primary key definitions and primary key column names for serial conversion
# and save them
# Find foreign key constraints and collect them so we can add required indexes
open(F, "<$sourceDumpFile") || die;
while(<F>) {
    if (/^ALTER TABLE ONLY (\S+)/ .. /^\s*$/) {
        my $tablename = $1;
        if (/\s+ADD CONSTRAINT (\S+)_pkey (PRIMARY KEY .*);/) {
            my $pkdef = $2;
            $pk{$tablename} = $pkdef;
            if ($pkdef =~ /\(([a-z0-9_]+)\)/) {
                $pkc{$tablename} = $1;
            }
        }
        if (/\s+ADD CONSTRAINT (\S+) FOREIGN KEY \((\S+)\)/) {
            push @fk, "CREATE INDEX i_${tablename}_$1 ON $tablename ($2);";
        }
    }

    #ALTER TABLE ONLY alert
    #ADD CONSTRAINT a_customer_fk FOREIGN KEY (customer_id) REFERENCES customer(customer_id) ;

}
close(F);


open(F, "<$sourceDumpFile") || die;
open(D, ">$destDumpFile") || die;
my $curtable;
while(<F>) {
    # remove copy tables if $omitData is true
    if (/^COPY / .. /^\\\./) {
        $_ = "" if $omitData;
        next;
    } else {
      $_ = cleanUnsupportedKeywords($_);
    }

    if (/^CREATE SEQUENCE/ .. /^\s*$/) {
        $_ = "-- $_";
    }

    # In a create table we check the table name to see if we have a PK stanza saved to print 
    # at the end
    if (my $num = /^CREATE TABLE (\S+)/ .. /^\)/) {
        if ($num == 1) {
            $curtable = $1;
        }
        # if we are on the column that will be the pk, change the type to serial
        if ($pkc{$curtable} && /^\s+$pkc{$curtable} integer/) {
            s/integer/serial/;
        }
        if ($num =~ /E0/ && $pk{$curtable}) {
            print D ", $pk{$curtable}\n";
            $curtable = '';
        } else {
            # quote all column names that are not already quoted
            s/^(\s+)([^\" ]\S+)/$1"$2"/;
        }
    }

    # if we hit a create index, dump out the added ones for FKs we collcted in first pass
    if (/^CREATE INDEX/ && !$haveDumpedFKIndicies ) {
        $haveDumpedFKIndicies = 1;
        print D join("\n", @fk), "\n";
    }

    # If this is a PRIMARY KEY addition, we comment it out otherwise we leave it alone
    if (/^ALTER TABLE ONLY (\S+)/) {
        my $lookahead = <F>;
        $lookahead = cleanUnsupportedKeywords($lookahead);
        if ($lookahead =~ /PRIMARY KEY/) {
	  print D "-- $_";
	  print D "-- $lookahead";
	} else {
          print D $_;
          print D $lookahead;
	}
        $_ = "";
    }

} continue {
    print D;
}
close(F);
close(D);


sub cleanUnsupportedKeywords {
    my($f) = @_;
    $f =~ s/^(ALTER TABLE \S+ OWNER |CREATE EXTENSION|COMMENT ON|ALTER SEQUENCE|ALTER TABLE.*nextval|SELECT pg_catalog)|GRANT|REVOKE/-- \1/;
    $f =~ s/^(SET (?!client_encoding|standard_conforming_strings|client_min_messages|search_path))/-- \1/;
    $f =~ s/DEFERRABLE INITIALLY DEFERRED//;
    $f =~ s/ON DELETE SET NULL//;
    $f =~ s/USING btree //;
    if (!$v2) {
      $f =~ s/^(COMMENT ON)/-- \1/;
    }
    return $f;
}


#ERROR:  expected 17 values, got 16
