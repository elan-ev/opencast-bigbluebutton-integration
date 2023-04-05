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
- Based on BigBlueButton configuration a single file recording can be transfered (see [Configure Single File Recording](#configure-single-file-recording))

Requirements
------------

- The Ruby gem `rest-client` is used to send requests to Opencast.
If it is not yet installed, add the line `gem 'rest-client'` to the `GEMFILE` located at `/usr/local/bigbluebutton/core/Gemfile`. If not already present in the gemfile, you also need to add `gem 'toml-rb'` and `gem 'shellwords'`. Finally, you need to run `bundle install` to install the gems.

Set Up BigBlueButton
----------------------

What we want to add in BigBlueButton is a post processing script as [described in the documentation](https://docs.bigbluebutton.org/dev/recording.html#writing-post-scripts).
This script should be located at (there should already be an example script in that folder):

    /usr/local/bigbluebutton/core/scripts/post_publish/post_publish.rb

Make sure to adjust the credentials set at the top of this script.

Place the folder `oc_modules` from the top-level of this repository in the same location as the script. It contains
modules that are necessary for the script to run.

    /usr/local/bigbluebutton/core/scripts/post_publish/oc_modules

Configure Single File Recording
-------------------------------

The single file recording contains webcams, presentation including markings, screensharing, poll results and audio. This file does not include chat, notes, users list and shared external videos. This recording provides an alternative to the separate video files that are uploaded to Opencast. To process and transfer these recordings, you need to enable the `video` format on your BigBlueButton server.

1. Install the package:

        apt-get install bbb-playback-video

2. Edit `/usr/local/bigbluebutton/core/scripts/bigbluebutton.yml`:

        steps:
            archive: "sanity"
            sanity: "captions"
            captions:
                - "process:presentation"
                - "process:video"
            "process:presentation": "publish:presentation"
            "process:video": "publish:video"

    Alternatively, if you want to process and transfer only the single recording file, remove in `steps` the lines of the "presentation" format as follows:

        steps:
            archive: "sanity"
            sanity: "captions"
            captions: "process:video"
            "process:video": "publish:video"

3. Restart processes:

        systemctl restart bbb-rap-resque-worker.service nginx

For more details, see [Install additional recording processing formats](https://docs.bigbluebutton.org/administration/customize/#install-additional-recording-processing-formats).

Limitations
-----------

This is a very simple integration, but should work just fine.
Nevertheless, there are a few limitations.

- BigBlueButton includes audio only in the camera recording, not in the screen recording.
  Your Opencast workflow will need to fix that.
