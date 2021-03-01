Post-Publish Integration
========================

This mostly follows the [original blog post on weblog.lkiesow.de](https://weblog.lkiesow.de/20200318-integrate-bigbluebutton-opencast/).

The Idea
--------

- Let BigBlueButton process the recordings
- Send them to Opencast once they are finished
- Transferred media includes:
    - Combined video of all webcams
    - Video of Screen recording
    - Combined audio
    
Requirements
------------

- The Ruby gem 'rest-client' is used to send requests to Opencast. If it is not yet installed, manually install it
  via `gem install *name*`.


The Integration Script
----------------------

What we want to add in BigBlueButton is a post processing script as [described in the documentation](https://docs.bigbluebutton.org/dev/recording.html#writing-post-scripts).
This script should be located at (there should already be an example script in that folder):

    /usr/local/bigbluebutton/core/scripts/post_publish/post_publish.rb

Make sure to adjust the credentials set at the top of this script.

Place the folder `oc_modules` from the top-level of this repository in the same location as the script. It contains
modules that are necessary for the script to run.

    /usr/local/bigbluebutton/core/scripts/post_publish/oc_modules


Limitations
-----------

This is a very simple integration, but should work just fine.
Nevertheless, there are a few limitations.

- BigBlueButton includes audio only in the camera recording, not in the screen recording.
  Your Opencast workflow will need to fix that.
