Post-Archive Integration
========================

**There is a known bug where the final video in Opencast will be too short due to missing parts of the recording. A
  workaround is currently not available for Opencast 8!!!, but will be available with Opencast 9.**
- If you wish to have the workaround available in Opencast 8, you will have to backport [Opencast Pull Request #1898](https://github.com/opencast/opencast/pull/1898)
    - You will also have to uncomment two lines in the `bbb-upload.xml`
    
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
    
    Place the folder `oc_modules` from the top-level of this repository in the same location. 
    
    `/usr/local/bigbluebutton/core/scripts/post_archive/oc_modules`
- In the script `post_archive.rb`, change the global variables in the "opencast configuration":
	- In `post_archive.rb`, change the variable `$oc_server` to point to your Opencast installation
	- Also change `$oc_user` and `oc_password` to a user of your opencast installation that is allowed to ingest (e.g. 
	  ROLE_ADMIN)
	    - Alternatively, you can use ROLE_CAPTURE_AGENT for more restricted access rights
	- Change the remaining options how you like.
    - When using with Opencast 9.1 (or higher): Remove the following line from `post_archive.rb` to enable webcam support.    
      `break   # Stop after first iteration to only send first webcam file found. TODO: Teach Opencast to deal with webcam file`
- Disable the process and publish steps by calling: `sudo bbb-record --disable presentation`
- Ensure BBB is configured for recording. In `/usr/share/bbb-web/WEB-INF/classes/bigbluebutton.properties` the parameter
  `disableRecordingDefault` should be set to false.
	- In the same file, set `autoStartRecording` to true and `allowStartStopRecording` to false to reflect the current limitations.
	    - Skip this step when using Opencast 9.2 with automatic recording enabled.
	- For changes in bigbluebutton.properties to take effect, BBB needs to be restarted using `bbb-conf --restart`
- Depending on your deployment process, the two above BBB configuration changes may get overwritten when updating BBB.
  To ensure that does not happen, you can use `apply-config.sh` bash script offered by BBB (Details at: https://docs.bigbluebutton.org/2.2/customize.html#apply-confsh)
- Allow post scripts to call the `bbb-record` utility by adding the line `bigbluebutton ALL = NOPASSWD: /usr/bin/bbb-record` 
  to `/etc/sudoers`

Setup Opencast
--------
- In your Opencast installation, add the file `bbb-upload.xml` to the workflow folder (Likely located at `etc/workflows` 
  or `etc/opencast/workflows`)
  - When using Opencast 9.1: Use `bbb-upload-9.xml` instead of `bbb-upload.xml` to also enable webcams. Make sure to only have one of them in your Workflow directory.
  - When using Opencast 9.2 (or higher): Use `bbb-upload-9-2.xml` instead of `bbb-upload.xml` to also enable automatic cutting. Make sure to only have one of them in your Workflow directory.
- Add the file `bbb-publish-after-cutting.xml`. This will add a new Publish option to the VideoEditor, which needs to be 
  used when cutting videos after they have been uploaded from BBB.
- In the Admin-UI, create the user you entered in the post_archive.rb during "Setup BBB"
- When using Opencast 8.6 or lower: Apply a fix in the file `/etc/encoding/opencast-images.properties` by assigning the 
  variable `profile.import.image-frame.ffmpeg.command` the value 
  `-sseof -3 -i #{in.video.path} -update 1 -q:v 1 #{out.dir}/#{out.name}#{out.suffix}`.

Limitations & Take Cares
--------
- Currently, only audio, deskshare, raw slides (no marks) and one webcam file are transmitted.
    - **When using Opencast 9.1** or higher, webcams can be enabled. This will generate a single video file from all the webcam recordings. Details can be found in the setup instructions.
- Currently processes and publishes the WHOLE conference, not just when you click the start/stop recording button
	- To get rid of the parts you don't want, use the video editor tool in Opencast
	- **When using Opencast 9.2** or higher, automatic cutting can be enabled. This will cut the video files in accordance with the start/stop button being pressed. Details can be found in the setup instructions.
- After successfully transmitting the recording to Opencast, all data related to the recording on the BBB installation WILL BE DELETED!
	- If you don't want that, comment out the line under the comment `# Delete all raw recording data` in the function `cleanup`
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
