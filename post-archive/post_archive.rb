require 'trollop'         #Commandline Parser
require 'rest-client'     #Easier HTTP Requests
require 'nokogiri'        #XML-Parser
require 'fileutils'       #Directory Creation
require 'streamio-ffmpeg' #Accessing video information
require 'Socket'          #Debugging hostname
require File.expand_path('../../../lib/recordandplayback', __FILE__)  # BBB Utilities

require_relative 'oc_modules/oc_dublincore'
require_relative 'oc_modules/oc_acl'
require_relative 'oc_modules/oc_util'

### opencast configuration begin

# Server URL
# oc_server = 'https://develop.opencast.org'
$oc_server = 'http://my-opencast.org'

# User credentials allowed to ingest via HTTP basic
# oc_user = 'username'
# oc_password = 'password'
$oc_user = 'admin'
$oc_password = 'opencast'

# Workflow to use for ingest
# oc_workflow = 'bbb-upload'
$oc_workflow = 'bbb-upload'

# Removes the raw recording data from BBB if the script sent all the data to Opencast successfully.
# Set to false if there are other post_archive scripts after this one, or else they will
# likely fail due to the missing data.
# Although data will only ever be deleted after the script was successful and the first thing
# Opencast does (in the bbb-upload Workflow) is to make a snapshot of all the data it got,
# there may still be edge cases where data loss can occur. If you absolutely cannot accept
# any data loss, set this option to false.
# Suggested default: true
$deleteIfSuccessful = true

# Marks the raw recording data for deletion by the BBB clean-up cron job.
# This will have no effect if the cron job is disabled.
# This will have no effect if "$deleteIfSuccessful" is set to true.
# Suggested default: false
$deleteByBBBCron = false

# Send the webcam recording to Opencast.
# If your Opencast is any version earlier than 9.1, you MUST set this to false.
# Suggest default: true
$addWebcamTracks = true

# Adds the shared notes etherpad from a meeting to the attachments in Opencast
# Suggested default: false
$sendSharedNotesEtherpadAsAttachment = false

# Adds the public chat from a meeting to the attachments in Opencast as a subtitle file
# Suggested default: false
$sendChatAsSubtitleAttachment = false

# Adds a debug file to the assets/attachements of a media package in Opencast
$sendDebugAttachment = false

# Add all uploaded presentations from a meeting to the attachments in Opencast as PDF files.
# Please make sure to use this feature respectfully.
# Suggested default: false
$sendPresentationsAsPdf = false

# Default roles for the event, e.g. "ROLE_OAUTH_USER, ROLE_USER_BOB"
# Suggested default: ""
$defaultRolesWithReadPerm = ''
$defaultRolesWithWritePerm = ''

# Whether a new series should be created if the given one does not exist yet
# Suggested default: false
$createNewSeriesIfItDoesNotYetExist = false

# Default roles for the series, e.g. "ROLE_OAUTH_USER, ROLE_USER_BOB"
# Suggested default: ""
$defaultSeriesRolesWithReadPerm = ''
$defaultSeriesRolesWithWritePerm = ''

# The given dublincore identifier will also passed to the dublincore source tag,
# even if the given identifier cannot be used as the actual identifier for the vent
# Suggested default: false
$passIdentifierAsDcSource = false

# Flow control booleans
# Suggested default: false
$onlyIngestIfRecordButtonWasPressed = false

# If a converted video already exists, don't overwrite it
# This can save time when having to run this script on the same input multiple times
# Suggested default: false
$doNotConvertVideosAgain = false

# Monitor Opencast workflow state after ingest to determine whether the workflow was successful.
# WARNING! Will stop processing of further recordings until the Opencast workflow completes. Do not use in production!
# EXPERIMENTIAL! This may cause the process spawned from this script to run a lot longer than anticipated.
# Suggested default: false
$monitorOpencastAfterIngest = false
# Time between each state check in seconds
$secondsBetweenChecks = 300
# Fail-safe. Time in seconds until the process is terminated no matter what.
$secondsUntilGiveUpMax = 86400

### opencast configuration end

#
# Parse TimeStamps - Start and End Time
#
# doc: file handle
#
# return: start and end time of the conference in ms (Unix EPOC)
#
def getRealStartEndTimes(doc)
  # Parse general time values | Stolen from bigbluebutton/record-and-playback/presentation/scripts/process/presentation.rb
  # Times in ms
  meeting_start = doc.xpath("//event")[0][:timestamp]
  meeting_end = doc.xpath("//event").last()[:timestamp]

  meeting_id = doc.at_xpath("//meeting")[:id]
  real_start_time = meeting_id.split('-').last
  real_end_time = (real_start_time.to_i + (meeting_end.to_i - meeting_start.to_i)).to_s

  real_start_time = real_start_time.to_i
  real_end_time = real_end_time.to_i

  return real_start_time, real_end_time
end

#
# Parse TimeStamps - All files and start times for a given event
#
# doc: file handle
# eventName: name of the xml tag attribute 'eventName', string
# resultArray: Where results will be appended to, array
# filePath: Path to the folder were the file related to the event will reside
#
# return: resultArray with appended hashes
#
def parseTimeStamps(doc, eventName, resultArray, filePath)
  doc.xpath("//event[@eventname='#{eventName}']").each do |item|
    newItem = Hash.new
    newItem["filename"] = item.at_xpath("filename").content.split('/').last
    newItem["timestamp"] = item.at_xpath("timestampUTC").content.to_i
    newItem["filepath"] = filePath
    if !File.exists?(File.join(newItem["filepath"], newItem["filename"]))
      next
    end
    resultArray.push(newItem)
  end

  return resultArray
end

#
# Parse TimeStamps - Recording marks start and stop
#
# doc: file handle
# eventName: name of the xml tag attribute 'eventName', string
# recordingStart: Where results will be appended to, array
# recordingStop: Where results will be appended to, array
#
# return: recordingStart, recordingStop arrays with timestamps
#
def parseTimeStampsRecording(doc, eventName, recordingStart, recordingStop, real_end_time)
  # Parse timestamps for Recording
  doc.xpath("//event[@eventname='#{eventName}']").each do |item|
    if item.at_xpath("status").content == "true"
      recordingStart.push(item.at_xpath("timestampUTC").content.to_i)
    else
      recordingStop.push(item.at_xpath("timestampUTC").content.to_i)
    end
  end

  if recordingStart.length > recordingStop.length
    recordingStop.push(real_end_time)
  end

  return recordingStart, recordingStop
end

#
# Parse TimeStamps - All files, start times and presentation for a given slide
#
# doc: file handle
# eventName: name of the xml tag attribute 'eventName', string
# resultArray: Where results will be appended to, array
# filePath: Path to the folder were the file related to the event will reside
#
# return: resultArray with appended hashes
#
def parseTimeStampsPresentation(doc, eventName, resultArray, filePath)
  doc.xpath("//event[@eventname='#{eventName}']").each do |item|
    newItem = Hash.new
    if(item.at_xpath("slide"))
      newItem["filename"] = "slide#{item.at_xpath("slide").content.to_i + 1}.svg" # Add 1 to fix index
    else
      newItem["filename"] = "slide1.svg"  # Assume slide 1
    end
    newItem["timestamp"] = item.at_xpath("timestampUTC").content.to_i
    newItem["filepath"] = File.join(filePath, item.at_xpath("presentationName").content, "svgs")
    newItem["presentationName"] = item.at_xpath("presentationName").content
    if !File.exists?(File.join(newItem["filepath"], newItem["filename"]))
      next
    end
    resultArray.push(newItem)
  end

  return resultArray
end

#
# Helper function for changing a filename string
#
def changeFileExtensionTo(filename, extension)
  return "#{File.basename(filename, File.extname(filename))}.#{extension}"
end

# def makeEven(number)
#   return number % 2 == 0 ? number : number + 1
# end

#
# Convert SVGs to MP4s
#
# SVGs are converted to PNGs first, since ffmpeg can to weird things with SVGs.
#
# presentationSlidesStart: array of numerics
#
# return: presentationSlidesStart, with filenames now pointing to the new videos
#
def convertSlidesToVideo(presentationSlidesStart)
  presentationSlidesStart.each do |item|
    # Path to original svg
    originalLocation = File.join(item["filepath"], item["filename"])
    # Save conversion with similar path in tmp
    dirname = File.join(TMP_PATH, item["presentationName"], "svgs")
    finalLocation = File.join(dirname, changeFileExtensionTo(item["filename"], "mp4"))

    if (!File.exists?(finalLocation))
      # Create path to save conversion to
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      # Convert to png using command line tool rsvg-convert
      image_format = 'png'
      pathToImage = File.join(dirname, changeFileExtensionTo(item["filename"], "png"))
      `rsvg-convert #{originalLocation} -f #{image_format} --width 2560 --background-color white -o #{pathToImage}`

      # Convert to video
      # Scales the output to be divisible by 2
      system "ffmpeg -loglevel quiet -nostdin -nostats -y -r 30 -i #{pathToImage} -vf crop='trunc(iw/2)*2:trunc(ih/2)*2' #{finalLocation}"
    end

    item["filepath"] = dirname
    item["filename"] = finalLocation.split('/').last
  end

  return presentationSlidesStart
end

#
# Checks if the video requires transcoding before sending it to Opencast
# * Checks if a video has a width and height that is divisible by 2
#   If not, crops the video to have one 
# * Checks if the video is missing duration metadata
#   If it's missing, copies the video to add it
#
# path: string, path to the file in question (without the filename)
# filename: string, name of the file (with extension)
#
# return: new path to the file (keeps the filename)
#
def checkForTranscode(path, filename)
  pathToFile = File.join(path, filename)
  outputPathToFile = File.join(TMP_PATH, pathToFile)

  if ($doNotConvertVideosAgain && File.exists?(outputPathToFile))
    BigBlueButton.logger.info( "Converted video for #{pathToFile} already exists, skipping...")
    return outputPathToFile
  end

  # Gather possible commands
  transcodeCommands = []
  movie = FFMPEG::Movie.new(pathToFile)
  unless (movie.width % 2 == 0 && movie.height % 2 == 0)
    BigBlueButton.logger.info( "Video #{pathToFile} requires cropping to be DivBy2")
    transcodeCommands.push(%w(-y -r 30 -vf crop=trunc(iw/2)*2:trunc(ih/2)*2))
  end
  if (movie.duration <= 0)
    BigBlueButton.logger.info( "Video #{pathToFile} requires transcoding due to missing duration")
    transcodeCommands.push(%w(-y -c copy))
  end

  # Run gathered commands
  if(transcodeCommands.length == 0)
    BigBlueButton.logger.info( "Video #{pathToFile} is fine")
    return path
  else
    # Create path to save conversion to
    outputPath = File.join(TMP_PATH, path)
    unless File.directory?(outputPath)
      FileUtils.mkdir_p(outputPath)
    end

    BigBlueButton.logger.info( "Start converting #{pathToFile} ...")
    transcodeCommands.each do | command |
      BigBlueButton.logger.info( "Running ffmpeg with options: #{command}")
      movie.transcode(outputPath + 'tmp' + filename, command)
      FileUtils.mv(outputPath + 'tmp' + filename, outputPathToFile)
      movie = FFMPEG::Movie.new(outputPathToFile)   # Further transcoding should happen on the new file
    end

    BigBlueButton.logger.info( "Done converting #{pathToFile}")
    return outputPath
  end
end

#
# Collect file information
#
# tracks: Structure containing information on each file, array of hashes
# flavor: Whether the file is part of presenter or presentation, string
# startTimes: When each file was started to be recorded in ms, array of numerics
# real_start_time: Starting timestamp of the conference
#
# return: tracks + new tracks found at directory_path
#

def collectFileInformation(tracks, flavor, startTimes, real_start_time)
  startTimes.each do |file|
    pathToFile = File.join(file["filepath"], file["filename"])

    BigBlueButton.logger.info( "PathToFile: #{pathToFile}")

    if (File.exists?(pathToFile))
      # File Integrity check
      if (!FFMPEG::Movie.new(pathToFile).valid?)
        BigBlueButton.logger.info( "The file #{pathToFile} is ffmpeg-invalid and won't be ingested")
        next
      end

      tracks.push( { "flavor": flavor,
                    "startTime": file["timestamp"] - real_start_time,
                    "path": pathToFile
      } )
    end
  end

  return tracks
end

# Write debugging information to JSON file at path
#
# path: Location to save JSON to, string
# debugEntries: Hash of entries
# 
# return: null
def createDebugJSONAtPath(path, debugEntries)
  debugEntries.store("hostname", Socket.gethostname)
  debugEntries.store("meeting_id", meeting_id)
  debugEntries.store("workflow_on_ingest", oc_workflow)
  debugEntries.store("post_archive_VIDEO_PATH", VIDEO_PATH)
  debugEntries.store("post_archive_AUDIO_PATH", AUDIO_PATH)
  File.write(path, JSON.pretty_generate(debugEntries))
end

#
# Creates a JSON for sending cutting marks
#
# path: Location to save JSON to, string
# recordingStart: Start marks, array
# recordingStop: Stop marks, array
# real_start_time: Start time of the conference
# real_end_time: End time of the conference
#
def createCuttingMarksJSONAtPath(path, recordingStart, recordingStop, real_start_time, real_end_time)
  tmpTimes = []

  index = 0
  recordingStart.each do |startStamp|
    stopStamp = recordingStop[index]

    tmpTimes.push( {
      "begin" => startStamp - real_start_time,
      "duration" => stopStamp - startStamp
    } )
    index += 1
  end

  File.write(path, JSON.pretty_generate(tmpTimes))
end

#
# Parses the chat messages from the events.xml into a webvtt subtitles file
# TODO: Sanitize chat messages?
#
# doc: file handle
# chatFilePath: string
# realStartTime: number, start time of the meeting in epoch time
# recordingStart: array[string], times when the recording button was pressed in epoch time
# recordingStop: array[string], times when the recording button was pressed in epoch time
#
def parseChat(doc, chatFilePath, realStartTime, recordingStart, recordingStop)
  BigBlueButton.logger.info( "Parsing chat messages")

  timeFormat = '%H:%M:%S.%L'
  displayMessageTimeMax = 3  # seconds
  chatMessages = []

  # Gather messages
  chatEvents = doc.xpath("//event[@eventname='PublicChatEvent']")

  recordingStart.each.with_index do |recordStartStamp, index|
    recordStopStamp = recordingStop[index]

    chatEvents.each do |node|
      chatTimestamp = node.at_xpath("timestampUTC").content.to_i

      if (chatTimestamp >= recordStartStamp.to_i and chatTimestamp <= recordStopStamp.to_i)
        chatSender = node.xpath(".//sender")[0].text()
        chatMessage =  node.xpath(".//message")[0].text()
        chatStart = Time.at((chatTimestamp - realStartTime) / 1000.0) #.utc.strftime(TIME_FORMAT)
        #chatEnd = Time.at((chatTimestamp - realStartTime) / 1000.0) + 2
        #chatEnd = chatEnd.utc.strftime(TIME_FORMAT)
        chatMessages.push({sender: chatSender,
          message: chatMessage,
          startTime: chatStart,
          endTime: Time.at(0)
        })
      end
    end

  end

  # Update timestamps
  chatMessages.each.with_index do |message, index|
    # Last message
    if chatMessages[index + 1].nil?
      message[:endTime] = message[:startTime] + displayMessageTimeMax
      break
    end

    if (chatMessages[index + 1][:startTime] - message[:startTime]) < displayMessageTimeMax
      message[:endTime] = chatMessages[index + 1][:startTime]
    else
      message[:endTime] = message[:startTime] + displayMessageTimeMax
    end
  end

  # Compile messages
  files = []
  files.push("WEBVTT")
  files.push("")
  chatMessages.each do |message|
    files.push(message[:startTime].utc.strftime(timeFormat).to_s + " --> " + message[:endTime].utc.strftime(timeFormat).to_s)
    files.push(message[:sender] + ": " + message[:message])
    files.push("")
  end

  if (chatMessages.length > 0)
    File.write(chatFilePath, files.join("\n"))
  end
end

#
# Monitors the state of the started workflow after ingest
# Will run for quite some time
#
def monitorOpencastWorkflow(ingestResponse, secondsBetweenChecks, secondsUntilGiveUpMax, meetingId)

  ### Wait for Opencast to be done
  secondsUntilGiveUpCounter = 0
  isOpencastDoneYet = false

  # Get the id of the workflow
  doc = Nokogiri::XML(ingestResponse)
  workflowID = doc.xpath("//wf:workflow")[0].attr('id')
  mediapackageID = doc.xpath("//mp:mediapackage")[0].attr('id')

  # Keep checking whether the started workflow is still running or not
  while !isOpencastDoneYet do
    # Wait between checks
    sleep(secondsBetweenChecks)

    # Request check
    response = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                :get, '/workflow/instance/' + workflowID + '.xml', DEFAULT_REQUEST_TIMEOUT, {},
                "There has been a problem in OC with the workflow for mediapackage " + mediapackageID + " for BBB recording " + meetingId + ". Aborting..." )

    # Request workflow information
    doc = Nokogiri::XML(response)
    elems = doc.xpath("//wf:workflow")
    state = elems[0].attr('state')

    # Check state
    if (state == "SUCCEEDED")
      BigBlueButton.logger.info( "Workflow for " + mediapackageID + " succeeded.")
      isOpencastDoneYet = true
    elsif (state == "RUNNING" || state == "INSTANTIATED")
      BigBlueButton.logger.info( "Workflow for " + mediapackageID + " is " + state)
    else
      BigBlueButton.logger.error(" Workflow for " + mediapackageID + " is in state + " + state + ", meaning it is neither running nor has it succeeded. Recording data for " + meetingId + " will not be cleaned up. Aborting...")
      exit 1
    end

    # Fail-safe. End this process after some time has passed.
    secondsUntilGiveUpCounter += secondsBetweenChecks
    if ( secondsUntilGiveUpCounter >= secondsUntilGiveUpMax )
      BigBlueButton.logger.error(" " + secondsUntilGiveUpMax.to_s + " seconds have passed since the mediapackage with id " + mediapackageID + " was ingested. Mercy killing process for recording " + meeting_id)
      exit 1
    end

  end
end

#
# Anything and everything that should be done just before the program successfully terminates for any reason
#
# tmp_path: string, path to local temporary directory
# meeting_id: numeric, id of the current meeting
#
def cleanup(tmp_path, meeting_id)
  # Delete temporary files
  FileUtils.rm_rf(tmp_path)

  # Inform BBB that the recording was successfully processed
  if ($deleteByBBBCron)
    BigBlueButton.logger.info( "Inform BBB daily cron about the \"successful publish\" of this meeting #{meeting_id}")
    File.open("/var/bigbluebutton/recording/status/published/#{meeting_id}-presentation.done", ["w"]) {|f| f.write("Published #{meeting_id}") }
  end

  # Delete all raw recording data
  # TODO: Find a way to outsource this into a script that runs after all post_archive scripts have run successfully
  if ($deleteIfSuccessful)
    BigBlueButton.logger.info( "Attempting to delete raw recording data for meeting #{meeting_id}")
    system('sudo', 'bbb-record', '--delete', "#{meeting_id}") || raise('Failed to delete local recording')
  end
end

#########################################################
################## START ################################
#########################################################

### Initialization begin

#
# Parse cmd args from BBB and initialize logger

opts = Trollop::options do
  opt :meeting_id, "Meeting id to archive", :type => String
end
meeting_id = opts[:meeting_id]

logger = Logger.new("/var/log/bigbluebutton/post_archive.log", 'weekly' )
logger.level = Logger::INFO
BigBlueButton.logger = logger

archived_files = "/var/bigbluebutton/recording/raw/#{meeting_id}"
meeting_metadata = BigBlueButton::Events.get_meeting_metadata("#{archived_files}/events.xml")
xml_path = archived_files +"/events.xml"
BigBlueButton.logger.info("Series id: #{meeting_metadata["opencast-series-id"]}")

# Variables
mediapackage = ''
deskshareStart = []           # Array of timestamps
webcamStart = []              # Array of hashes[filename, timestamp]
audioStart = []               # Array of hashes[filename, timestamp]
recordingStart = []           # Array of timestamps
recordingStop = []            # Array of timestamps
presentationSlidesStart = []  # Array of hashes[filename, timestamp, presentationName]
tracks = []                   # Array of hashes[flavor, starttime, path]
debugEntries = []             # Hashmap of key-value pairs for tracing archived bbb videos

# Constants
DEFAULT_REQUEST_TIMEOUT = 10                                  # Http request timeout in seconds
START_WORKFLOW_REQUEST_TIMEOUT = 6000                         # Specific timeout; Opencast runs MediaInspector on every file, which can take quite a while
CUTTING_MARKS_FLAVOR = "json/times"

VIDEO_PATH = File.join(archived_files, 'video', meeting_id)    # Path defined by BBB
AUDIO_PATH = File.join(archived_files, 'audio')                # Path defined by BBB
DESKSHARE_PATH = File.join(archived_files, 'deskshare')        # Path defined by BBB
PRESENTATION_PATH = File.join(archived_files, 'presentation')  # Path defined by BBB
SHARED_NOTES_PATH = File.join(archived_files, 'notes')         # Path defined by BBB
TMP_PATH = File.join(archived_files, 'upload_tmp')             # Where temporary files can be stored
CUTTING_JSON_PATH = File.join(TMP_PATH, "cutting.json")
CHAT_PATH = File.join(TMP_PATH, "chat.vtt")
ACL_PATH = File.join(TMP_PATH, "acl.xml")
DEBUG_PATH = File.join(TMP_PATH, "debug.json")

# Create local tmp directory
unless File.directory?(TMP_PATH)
  FileUtils.mkdir_p(TMP_PATH)
end

# Convert metadata keys to lowercase
# Transform_Keys is only available from ruby 2.5 onward :(
#metadata = metadata.transform_keys(&:downcase)
tmp_metadata = {}
meeting_metadata.each do |key, value|
  tmp_metadata["#{key.downcase}"] = meeting_metadata.delete("#{key}")
end
meeting_metadata = tmp_metadata

### Initialization end

#
# Parse TimeStamps
#

# Get events file handle
doc = ''
if(File.file?(xml_path))
  doc = Nokogiri::XML(File.open(xml_path))
else
  BigBlueButton.logger.error(": NO EVENTS.XML for recording" + meeting_id + "! Nothing to parse, aborting...")
  exit 1
end

# Get conference start and end timestamps in ms
real_start_time, real_end_time = getRealStartEndTimes(doc)
# Get screen share start timestamps
deskshareStart = parseTimeStamps(doc, 'StartWebRTCDesktopShareEvent', deskshareStart, DESKSHARE_PATH)
# Get webcam share start timestamps
webcamStart = parseTimeStamps(doc, 'StartWebRTCShareEvent', webcamStart, VIDEO_PATH)
# Get audio recording start timestamps
audioStart = parseTimeStamps(doc, 'StartRecordingEvent', audioStart, AUDIO_PATH)
# Get cut marks
recordingStart, recordingStop = parseTimeStampsRecording(doc, 'RecordStatusEvent', recordingStart, recordingStop, real_end_time)
# Get presentation slide start stamps
presentationSlidesStart = parseTimeStampsPresentation(doc, 'SharePresentationEvent', presentationSlidesStart, PRESENTATION_PATH) # Grab a timestamp for the beginning
presentationSlidesStart = parseTimeStampsPresentation(doc, 'GotoSlideEvent', presentationSlidesStart, PRESENTATION_PATH) # Grab timestamps from Goto events

# Opencasts addPartialTrack cannot handle files without a duration,
# therefore images need to be converted to videos.
presentationSlidesStart = convertSlidesToVideo(presentationSlidesStart)

# Check and process any videos if they need to be prepared before Opencast can process them
webcamStart.each do |share|
  share["filepath"] = checkForTranscode(share["filepath"], share["filename"])
end

# Exit program if the recording was not pressed
if ($onlyIngestIfRecordButtonWasPressed && recordingStart.length == 0)
  BigBlueButton.logger.info( "Recording Button was not pressed, aborting...")
  cleanup(TMP_PATH, meeting_id)
  exit 0
# Or instead assume that everything should be recorded
elsif (!$onlyIngestIfRecordButtonWasPressed && recordingStart.length == 0)
  recordingStart.push(real_start_time)
  recordingStop.push(real_end_time)
end

#
# Prepare information to be send to Opencast
# Tracks are ingested on a per file basis, so iterate through all files that should be send
#

# Add webcam tracks
if ($addWebcamTracks)
  tracks = collectFileInformation(tracks, 'presenter/source', webcamStart, real_start_time)
end
# Add audio tracks (Likely to be only one track)
tracks = collectFileInformation(tracks, 'presentation/source', audioStart, real_start_time)
# Add screen share tracks
tracks = collectFileInformation(tracks, 'presentation/source', deskshareStart, real_start_time)
# Add the previously generated tracks for presentation slides
tracks = collectFileInformation(tracks, 'presentation/source', presentationSlidesStart, real_start_time)

if(tracks.length == 0)
  BigBlueButton.logger.warn(" There are no files, nothing to do here")
  cleanup(TMP_PATH, meeting_id)
  exit 0
end

# Sort tracks in ascending order by their startTime, as is required by PartialImportWOH
tracks = tracks.sort_by { |k| k[:startTime] }
BigBlueButton.logger.info( "Sorted tracks: ")
BigBlueButton.logger.info( tracks)

# Create metadata file dublincore
dc_data = OcDublincore::parseDcMetadata(meeting_metadata, startTime: real_start_time, stopTime: real_end_time,
                                        server: $oc_server, user: $oc_user, password: $oc_password)
dublincore = OcDublincore::createDublincore(dc_data)
BigBlueButton.logger.info( "Dublincore: \n" + dublincore.to_s)

# Create Json containing cutting marks at path
createCuttingMarksJSONAtPath(CUTTING_JSON_PATH, recordingStart, recordingStop, real_start_time, real_end_time)

# Create ACLs at path
aclData = OcAcl::parseEpisodeAclMetadata(meeting_metadata, $defaultRolesWithReadPerm, $defaultRolesWithWritePerm)
if (!aclData.nil? && !aclData.empty?)
  File.write(ACL_PATH, OcAcl::createAcl(aclData))
end

# Create series with given seriesId, if such a series does not yet exist
if ($createNewSeriesIfItDoesNotYetExist)
  OcAcl::createSeries(meeting_metadata, $oc_server, $oc_user, $oc_password, $defaultSeriesRolesWithReadPerm, $defaultSeriesRolesWithWritePerm)
end

# Create a subtitles file from chat
if ($sendChatAsSubtitleAttachment)
  parseChat(doc, CHAT_PATH, real_start_time, recordingStart, recordingStop)
end

# Create debug entries file from debugEntries
if ($sendDebugAttachment)
  createDebugJSONAtPath(DEBUG_PATH, debugEntries)
end

#
# Create a mediapackage and ingest it
#

# Create Mediapackage
if !dc_data[:identifier].to_s.empty?
  mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                  :put, '/ingest/createMediaPackageWithID/' + dc_data[:identifier], DEFAULT_REQUEST_TIMEOUT,{})
else
  mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                  :get, '/ingest/createMediaPackage', DEFAULT_REQUEST_TIMEOUT, {})
end
BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
# Get mediapackageId for debugging
doc = Nokogiri::XML(mediapackage)
mediapackageId = doc.xpath("/*")[0].attr('id')
# Add Partial Track
tracks.each do |track|
  BigBlueButton.logger.info( "Track: " + track.to_s)
  mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                  :post, '/ingest/addPartialTrack', DEFAULT_REQUEST_TIMEOUT,
                  { :flavor => track[:flavor],
                    :startTime => track[:startTime],
                    :mediaPackage => mediapackage,
                    :body => File.open(track[:path], 'rb') })
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
end
# Add dublincore
mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                :post, '/ingest/addDCCatalog', DEFAULT_REQUEST_TIMEOUT,
                {:mediaPackage => mediapackage,
                 :dublinCore => dublincore })
BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
# Add cutting marks
mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                :post, '/ingest/addCatalog', DEFAULT_REQUEST_TIMEOUT,
                {:mediaPackage => mediapackage,
                 :flavor => CUTTING_MARKS_FLAVOR,
                 :body => File.open(CUTTING_JSON_PATH, 'rb')})
                 #:body => File.open(File.join(archived_files, "cutting.json"), 'rb')})

BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
# Add ACL
if (File.file?(ACL_PATH))
  mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                  :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                  {:mediaPackage => mediapackage,
                  :flavor => "security/xacml+episode",
                  :body => File.open(ACL_PATH, 'rb') })
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
else
  BigBlueButton.logger.info( "No ACL found, skipping adding ACL.")
end
# Add Shared Notes
if ($sendSharedNotesEtherpadAsAttachment && File.file?(File.join(SHARED_NOTES_PATH, "notes.etherpad")))
  mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                  :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                  {:mediaPackage => mediapackage,
                  :flavor => "etherpad/sharednotes",
                  :body => File.open(File.join(SHARED_NOTES_PATH, "notes.etherpad"), 'rb') })
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
else
  BigBlueButton.logger.info( "Adding Shared notes is either disabled or the etherpad was not found, skipping adding Shared Notes Etherpad.")
end
# Add Chat as subtitles
if ($sendChatAsSubtitleAttachment && File.file?(CHAT_PATH))
  mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                  :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                  {:mediaPackage => mediapackage,
                  :flavor => "captions/vtt+en",
                  :body => File.open(CHAT_PATH, 'rb') })
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
else
  BigBlueButton.logger.info( "Adding Chat as subtitles is either disabled or there was no chat, skipping adding Chat as subtitles.")
end
# Add presentations
if ($sendPresentationsAsPdf)
  presentationNames = presentationSlidesStart.map{|item| item["presentationName"]}.uniq
  presentationNames.each do |presentationName|
    presentationFilePath = File.join(PRESENTATION_PATH, presentationName, presentationName + ".pdf")
    if (File.exists?(presentationFilePath))
      mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                    :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                    {:mediaPackage => mediapackage,
                    :flavor => "presentation/pdf",
                    :body => File.open(presentationFilePath, 'rb') })
      BigBlueButton.logger.info( "Added presentation: #{presentationFilePath}")
    else
      BigBlueButton.logger.info( "Could not add: #{presentationFilePath}. File does not exist.")
    end
  end
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
else
  BigBlueButton.logger.info( "Adding Presentations as PDFs is disabled, skipping adding Presentations as PDFs.")
end
# Add debugging information
if ($sendDebugAttachment)
  if (File.file?(DEBUG_PATH))
    BigBlueButton.logger.info("Adding debugging information as attachment asset to MP::" + mediapackage)
    mediapackage = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password, 
                   :post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT, 
                   {:mediaPackage => mediapackage, 
                   :flavor => "json/debug", 
                   :body => File.open(DEBUG_PATH, 'rb') })
  else
    BigBlueButton.logger.info("Skipping sending debugging information to MP::" + mediapackage +  " because the file was not found.")
  end
  BigBlueButton.logger.info("Skipping sending debugging information to MP::" + mediapackage + " because sendDebugAttachment is disabled.")
end
# Ingest and start workflow
response = OcUtil::requestIngestAPI($oc_server, $oc_user, $oc_password,
                :post, '/ingest/ingest/' + $oc_workflow, START_WORKFLOW_REQUEST_TIMEOUT,
                { :mediaPackage => mediapackage },
                "LOG ERROR Aborting ingest with BBB id " + meeting_id + "and OC id" + mediapackageId )
BigBlueButton.logger.info( response)

### Monitor Opencast
if $monitorOpencastAfterIngest
  monitorOpencastWorkflow(response, $secondsBetweenChecks, $secondsUntilGiveUpMax, meeting_id)
end

### Exit gracefully
cleanup(TMP_PATH, meeting_id)
exit 0
