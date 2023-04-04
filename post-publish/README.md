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
    - Single file recording (see [Configure Single File Recording](#configure-single-file-recording))

Requirements
------------

- The Ruby gem `rest-client` is used to send requests to Opencast.
If it is not yet installed, add the line `gem 'rest-client'` to the `GEMFILE` located at `/usr/local/bigbluebutton/core/Gemfile`. Possibly, you also need to add `gem 'toml-rb'` and `gem 'shellwords'` to the `GEMFILE`.

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

The single file recording contains webcams, presentation and screensharing. This recording provides an alternative to the separate video files that are uploaded to Opencast. To process and transfer these recordings, you need to enable the `video` format on your BigBlueButton server.

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

    Alternative, if you don't want to process and upload the separate video files:

        steps:
            archive: "sanity"
            sanity: "captions"
            captions: "process:video"
            "process:video": "publish:video"

3. Restart processes:

        systemctl restart bbb-rap-resque-worker.service nginx

For more details, see [Install additional recording processing formats](https://docs.bigbluebutton.org/2.6/administration/customize#install-additional-recording-processing-formats).

Limitations
-----------

This is a very simple integration, but should work just fine.
Nevertheless, there are a few limitations.

- BigBlueButton includes audio only in the camera recording, not in the screen recording.
  Your Opencast workflow will need to fix that.
