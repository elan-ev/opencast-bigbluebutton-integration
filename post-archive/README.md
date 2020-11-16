Post-Archive Integration
========================

**There is a known bug where the final video in Opencast will be too short due to missing parts of the recording. A
  workaround is currently not available for Opencast 8!!!, but will be available with Opencast 9.**
- If you wish to have the workaround available in Opencast 8, you will have to backport [Opencast Pull Request #1898](https://github.com/opencast/opencast/pull/1898)

The Idea
--------

We want to record BigBlueButton meetings.  
But we don't want process and publish them through BBB, but with Opencast.  
So we send all the raw recording data from BBB to Opencast and process them with an Opencast workflow.  

Requirements
--------
- Opencast 8.4 (or later)
- BigBlueButton 2.2 (or later)
	- Ruby gems: rest-client, fileutils, mini_magick, streamio-ffmpeg

Files:
--------
post_archive.rb: A ruby script that handles sending data from BBB to Opencast.  
bbb-upload.xml: An Opencast workflow for processing BBB data.  
bbb-publish-after-cutting.xml: An Opencast workflow for publish an even that was processed with bbb-upload.xml in the VideoEditor.

Setup BBB
--------
- If the required ruby gems are not yet installed, manually install the ruby gems mentioned under requirements via `gem 
  install *name*`. They are used by the post_archive.rb script.
- Place the script `post_archive.rb` in 
    
    `/usr/local/bigbluebutton/core/scripts/post_archive/`
- In the script `post_archive.rb`, change the global variables in the "opencast configuration":
	- In `post_archive.rb`, change the variable `$oc_server` to point to your Opencast installation
	- Also change `$oc_user` and `oc_password` to a user of your opencast installation that is allowed to ingest (e.g. 
	  ROLE_ADMIN)
	    - Alternatively, you can use ROLE_CAPTURE_AGENT for more restricted access rights
	- Change the remaining options how you like.
- Disable the process and publish steps by calling: `sudo bbb-record --disable presentation`
- Allow post scripts to call the `bbb-record` utility by adding the line `bigbluebutton ALL = NOPASSWD: /usr/bin/bbb-record` 
  to `/etc/sudoers`
- Ensure BBB is configured for recording. In `/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties` the parameter
  `disableRecordingDefault` should be set to false.
	- In the same file, set `autoStartRecording` to true and `allowStartStopRecording` to false to reflect the current limitations.
	- For changes in bigbluebutton.properties to take effect, BBB needs to be restarted using `bbb-conf --restart`

Setup Opencast
--------
- In your Opencast installation, add the file `bbb-upload.xml` to the workflow folder (Likely located at `etc/workflows` 
  or `etc/opencast/workflows`)
- Add the file `bbb-publish-after-cutting.xml`. This will add a new Publish option to the VideoEditor, which needs to be 
  used when cutting videos after they have been uploaded from BBB.
- In the Admin-UI, create the user you entered in the post_archive.rb during "Setup BBB"
- Apply a fix in the file `/etc/encoding/opencast-images.properties` by assigning the 
  variable `profile.import.image-frame.ffmpeg.command` the value 
  `-sseof -3 -i #{in.video.path} -update 1 -q:v 1 #{out.dir}/#{out.name}#{out.suffix}`. This is fixed in Opencast 8.7.


Limitations & Take Cares
--------
- Currently, only audio, deskshare, raw slides (no marks) and one webcam file are transmitted. 
- After successfully transmitting the recording to Opencast, all data related to the recording on the BBB installation WILL BE DELETED!
	- If you don't want that, comment out the line under the comment `# Delete all raw recording data` in the function `cleanup`
- Currently processes and publishes the WHOLE conference, not just when you click the start/stop recording button
	- To get rid of the parts you don't want, use the video editor tool in Opencast
	- If you want to automate this you'll require the open pull request https://github.com/opencast/opencast/pull/1686 and changes to the bbb-upload workflow
- The recording is published with a few default metadata values. To set further metadata, the frontend which creates the
  BBB-Meeting will need pass them when calling the `/create` API, so that BBB then may pass them on to Opencast. 
  An overview over the possible metadata can be found [here](https://github.com/elan-ev/opencast-bigbluebutton-integration).
- The time between the end of a BBB Meeting and the recording appearing in Opencast depends largely on the number of 
  files generated. A simple test meeting should take something between 30-60 seconds. 
	- In certain edge cases (video recordings with uneven resolutions), there may still be some preprocessing necessary 
	  on BBB side, greatly increasing the time until the recording appears in Opencast.
- The BBB-Upload workflow for Opencast relies on the partial workflows `partial-preview.xml` and `partial-publish.xml`
  from the official Opencast installation. If these partial workflows are changed in your installation, you will need
  to change the BBB-Uploads workflows accordingly.
- When editing a video in the Videoeditor after it has been uploaded from BBB, use the option *Publish (BBB)* instead of
  the normal Publish.

Troubleshooting
--------
1. Opencast didn't get any data
	- Check the logs
		- `/var/log/bigbluebutton/bbb-rap-worker.log`, for potential exceptions
		- `/var/log/bigbluebutton/post_archive.log`, for additional information
	- Secure the recording data 
		- Or else it might get lost during regularly scheduled clean-ups
		- `/var/bigbluebutton/recording/raw/` is where the raw recording data is stored
	- If the problem could be resolved, try again
		- Run `sudo bbb-record --rebuild *path/to/recording*` on your BBB installation
		- `/var/bigbluebutton/recording/raw/` is where the raw recording data is stored
2. Opencast failed
	- ...
