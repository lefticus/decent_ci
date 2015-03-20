#!/usr/bin/python


from __future__ import print_function

import boto
import sys
import os
import datetime

conn = boto.connect_s3();
bucketname = sys.argv[1]
bucket = conn.get_bucket(bucketname)

buildname = sys.argv[2]
sourcedir = sys.argv[3]
destdir = sys.argv[4]

filedir = "{0}/{1}-{2}".format(destdir, datetime.datetime.now().date().isoformat(), buildname);


for root, subFolders, files in os.walk(sourcedir):
    for file in files:
        filename = os.path.join(root,file)
        filepath = "{0}/{1}".format(filedir, os.path.relpath(filename, sourcedir))
        print("{0} => {1}".format(filename, filepath), file=sys.stderr)
        key = boto.s3.key.Key(bucket, filepath)
        file_to_send = open(filename, 'r')
        if (filepath.endswith(".html")):
            content_type = {"Content-Type": "text/html"}
        elif (filepath.endswith(".svg")):
            content_type = {"Content-Type": "image/svg+xml"}
        else:
            content_type = {"Content-Type": "application/octect-stream"}

        key.set_contents_from_string(file_to_send.read(), headers=content_type)
        key.make_public()


print("http://{0}.s3-website-{1}.amazonaws.com/{2}".format(bucketname, "us-east-1", filedir))


