require 'trollop'     #Commandline Parser
require 'rest-client' #Easier HTTP Requests
require 'nokogiri'    #XML-Parser
require 'fileutils'   #Directory Creation
require 'mini_magick' #Image Conversion
require File.expand_path('../../../lib/recordandplayback', __FILE__)  # BBB Utilities

### opencast configuration begin

# Server URL
# oc_server = 'https://develop.opencast.org'
$oc_server = '{{opencast_server}}'

# User credentials allowed to ingest via HTTP basic
# oc_user = 'username'
# oc_password = 'password'
$oc_user = '{{opencast_user}}'
$oc_password = '{{opencast_password}}'

# Workflow to use for ingest
# oc_workflow = 'schedule-and-upload'
$oc_workflow = 'test-tag' #'bbb-upload'

# Booleans for processing metadata. False means 'nil' is used as fallback
# Suggested default: false
$useSharedNotesForDescriptionFallback = {{opencast_useSharedNotesFallback}}

# Default roles, e.g. "ROLE_OAUTH_USER, ROLE_USER_BOB"
# Suggested default: ""
$defaultRolesWithReadPerm = '{{opencast_rolesWithReadPerm}}'
$defaultRolesWithWritePerm = '{{opencast_rolesWithWritePerm}}'

# Whether a new series should be created if the given one does not exist yet
# Suggested default: false
$createNewSeriesIfItDoesNotYetExist = '{{opencast_createNewSeriesIfItDoesNotYetExist}}'

# Flow control booleans
# Suggested default: false
$onlyIngestIfRecordButtonWasPressed = '{{opencast_onlyIngestIfRecordButtonWasPressed}}'

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
#
# return: resultArray with appended hashes
#
def parseTimeStamps(doc, eventName, resultArray)
  doc.xpath("//event[@eventname='#{eventName}']").each do |item|
    newItem = Hash.new
    newItem["filename"] = item.at_xpath("filename").content.split('/').last
    newItem["timestamp"] = item.at_xpath("timestampUTC").content.to_i
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
#
# return: resultArray with appended hashes
#
def parseTimeStampsPresentation(doc, eventName, resultArray)
  doc.xpath("//event[@eventname='#{eventName}']").each do |item|
    newItem = Hash.new
    if(item.at_xpath("slide"))
      newItem["filename"] = "slide#{item.at_xpath("slide").content.to_i + 1}.svg" # Add 1 to fix index
    else
      newItem["filename"] = "slide1.svg"  # Assume slide 1
    end
    newItem["timestamp"] = item.at_xpath("timestampUTC").content.to_i
    newItem["presentationName"] = item.at_xpath("presentationName").content
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

def makeEven(number)
  return number % 2 == 0 ? number : number + 1
end

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
  # For every slide of every presentation
  (presentationSlidesStart.map { |h| h["presentationName"] }.uniq).each do |presentationName|
    Dir.foreach( File.join(PRESENTATION_PATH, presentationName, "svgs") ) do |filename|
      next if File.directory?(filename)

      # Path to original svg
      originalLocation = File.join(PRESENTATION_PATH, presentationName, "svgs", filename)
      # Create path to save conversion to
      dirname = File.join(TMP_PATH, presentationName, "svgs")
      unless File.directory?(dirname)
        FileUtils.mkdir_p(dirname)
      end

      # Convert to png
      image = MiniMagick::Image.open(originalLocation)
      image.format 'png'
      image.resize("#{makeEven(image.width)}x#{makeEven(image.height)}")           # Specify size to avoid accidental down-scaling
      pathToImage = File.join(dirname, changeFileExtensionTo(filename, "png"))
      image.write pathToImage

      # Save conversion with similar path in tmp
      finalLocation = File.join(TMP_PATH, presentationName, "svgs", changeFileExtensionTo(filename, "mp4"))
      BigBlueButton.logger.info( "Converting #{pathToImage} to #{finalLocation}")
      # Convert to video
      # Scales the output to be divisible by 2
      system "ffmpeg -loglevel quiet -nostdin -nostats -r 30 -i #{pathToImage} #{finalLocation}"
    end
  end

  # Rename stored filenames in accordance with the conversion
  presentationSlidesStart.each_with_index do |item, i|
    BigBlueButton.logger.info( "Renamed #{presentationSlidesStart[i]["filename"]}")
    presentationSlidesStart[i]["filename"] = changeFileExtensionTo(item["filename"], "mp4")
    BigBlueButton.logger.info( "To #{presentationSlidesStart[i]["filename"]}")
  end

  return presentationSlidesStart
end

#
# Collect file information
#
# directory_path: Path to directory with files, string
# tracks: Structure containing information on each file, array of hashes
# flavor: Whether the file is part of presenter or presentation, string
# startTimes: When each file was started to be recorded in ms, array of numerics
# real_start_time: Starting timestamp of the conference
#
# return: tracks + new tracks found at directory_path
#
def collectFileInformation(directory_path, tracks, flavor, startTimes, real_start_time)
  if (Dir.exist?(directory_path))
    Dir.foreach(directory_path) do |filename|
      next if File.directory?(filename)
      tracks.push( { "flavor": flavor,
                     "startTime": (startTimes.detect { |i| i["filename"] == filename }["timestamp"]) - real_start_time,
                     "path": File.join(directory_path, filename)
                   } )
    end
  end

  return tracks
end

#
# Helper function for creating xml nodes
#
def nokogiri_node_creator (doc, name, content, attributes = nil)
  new_node = Nokogiri::XML::Node.new(name, doc)
  new_node.content = content
  unless attributes.nil?
    attributes.each do |attribute|
      new_node.set_attribute(attribute[:name], attribute[:value])
    end
  end
  return new_node
end

#
# Creates a dublincore xml
#
# dc:data: array of hashes (symbol => string), contains the values for the different dublincore terms
#
# return: the complete xml, string
#
def createDublincore(dc_data)
  # A non-empty title is required for a successful ingest
  if dc_data[:title].to_s.empty?
    dc_data[:title] = "Default Title"
  end

  # Basic structure
  dublincore = []
  dublincore.push("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
  dublincore.push("<dublincore xmlns=\"http://www.opencastproject.org/xsd/1.0/dublincore/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">")
  dublincore.push("</dublincore>")
  dublincore = dublincore.join("\n")

  # Create nokogiri doc
  doc = Nokogiri::XML(dublincore)
  node_set = Nokogiri::XML::NodeSet.new(doc)

  # Create nokogiri nodes
  node_set << nokogiri_node_creator(doc, 'dcterms:title', dc_data[:title])
  node_set << nokogiri_node_creator(doc, 'dcterms:identifier', dc_data[:identifier])      if dc_data[:identifier]
  node_set << nokogiri_node_creator(doc, 'dcterms:creator', dc_data[:creator])            if dc_data[:creator]
  node_set << nokogiri_node_creator(doc, 'dcterms:isPartOf', dc_data[:isPartOf])          if dc_data[:isPartOf]
  node_set << nokogiri_node_creator(doc, 'dcterms:contributor', dc_data[:contributor])    if dc_data[:contributor]
  node_set << nokogiri_node_creator(doc, 'dcterms:subject', dc_data[:subject])            if dc_data[:subject]
  node_set << nokogiri_node_creator(doc, 'dcterms:language', dc_data[:language])          if dc_data[:language]
  node_set << nokogiri_node_creator(doc, 'dcterms:description', dc_data[:description])    if dc_data[:description]
  node_set << nokogiri_node_creator(doc, 'dcterms:spatial', dc_data[:spatial])            if dc_data[:spatial]
  node_set << nokogiri_node_creator(doc, 'dcterms:created', dc_data[:created])            if dc_data[:created]
  node_set << nokogiri_node_creator(doc, 'dcterms:rightsHolder', dc_data[:rightsHolder])  if dc_data[:rightsHolder]
  node_set << nokogiri_node_creator(doc, 'dcterms:license', dc_data[:license])            if dc_data[:license]
  node_set << nokogiri_node_creator(doc, 'dcterms:publisher', dc_data[:publisher])        if dc_data[:publisher]
  node_set << nokogiri_node_creator(doc, 'dcterms:temporal', dc_data[:temporal])          if dc_data[:temporal]

  # Add nodes
  doc.root.add_child(node_set)

  # Finalize
  return doc.to_xml
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
# Sends a web request to Opencast, using the credentials defined at the top
#
# method: Http method, symbol (e.g. :get, :post)
# url: ingest method, string (e.g. '/ingest/addPartialTrack')
# timeout: seconds until request returns with a timeout, numeric
# payload: information necessary for the request, hash
#
# return: The web request response
#
def requestIngestAPI(method, url, timeout, payload)
  begin
    response = RestClient::Request.new(
      :method => method,
      :url => $oc_server + url,
      :user => $oc_user,
      :password => $oc_password,
      :timeout => timeout,
      :payload => payload
    ).execute
  rescue RestClient::Exception => e
    BigBlueButton.logger.warn(" for request: #{url}")
    BigBlueButton.logger.info( e)
    BigBlueButton.logger.info( e.http_body)
    exit 1
  end

  return response
end

#
# Helper function that determines if the metadata in question exists
#
# metadata: hash (string => string)
# metadata_name: string, the key we hope exists in metadata
# fallback: object, what to return if it doesn't (or is empty)
#
# return: the value corresponding to metadata_name or fallback
#
def parseMetadataFieldOrFallback(metadata, metadata_name, fallback)
  return !(metadata[metadata_name.downcase].to_s.empty?) ?
           metadata[metadata_name.downcase] : fallback
end

#
# Creates a definition for metadata, containing symbol, identifier and fallback
#
# metadata: hash (string => string)
# meetingStartTime: time, as a fallback for the "created" metadata-field
#
# return: array of hashes
#
def getDcMetadataDefinition(metadata, meetingStartTime, meetingEndTime)
  dc_metadata_definition = []
  dc_metadata_definition.push( { :symbol   => :title,
                                 :fullName => "opencast-dc-title",
                                 :fallback => metadata['meetingname']})
  dc_metadata_definition.push( { :symbol   => :identifier,
                                 :fullName => "opencast-dc-identifier", 
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :creator,
                                 :fullName => "opencast-dc-creator",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :isPartOf,
                                 :fullName => "opencast-dc-ispartof",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :contributor,
                                 :fullName => "opencast-dc-contributor",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :subject,
                                 :fullName => "opencast-dc-subject",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :language,
                                 :fullName => "opencast-dc-language",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :description,
                                 :fullName => "opencast-dc-description",
                                 :fallback => $useSharedNotesForDescriptionFallback ? 
                                              sharedNotesToString(SHARED_NOTES_PATH) : nil})
  dc_metadata_definition.push( { :symbol   => :spatial,
                                 :fullName => "opencast-dc-spatial",
                                 :fallback => "BigBlueButton"})
  dc_metadata_definition.push( { :symbol   => :created,
                                 :fullName => "opencast-dc-created",
                                 :fallback => meetingStartTime})
  dc_metadata_definition.push( { :symbol   => :rightsHolder,
                                 :fullName => "opencast-dc-rightsholder",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :license,
                                 :fullName => "opencast-dc-license",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :publisher,
                                 :fullName => "opencast-dc-publisher",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :temporal,
                                 :fullName => "opencast-dc-temporal",
                                 :fallback => "start=#{Time.at(meetingStartTime / 1000).to_datetime}; 
                                               end=#{Time.at(meetingEndTime / 1000).to_datetime}; 
                                               scheme=W3C-DTF"})                                 
  return dc_metadata_definition
end

#
# Creates a definition for metadata, containing symbol, identifier and fallback
#
# metadata: hash (string => string)
# meetingStartTime: time, as a fallback for the "created" metadata-field
#
# return: array of hashes
#
def getSeriesDcMetadataDefinition(metadata, meetingStartTime)
  dc_metadata_definition = []
  dc_metadata_definition.push( { :symbol   => :title,
                                 :fullName => "opencast-series-dc-title",
                                 :fallback => metadata['meetingname']})
  dc_metadata_definition.push( { :symbol   => :identifier,
                                 :fullName => "opencast-dc-isPartOf",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :creator,
                                 :fullName => "opencast-series-dc-creator",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :contributor,
                                 :fullName => "opencast-series-dc-contributor",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :subject,
                                 :fullName => "opencast-series-dc-subject",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :language,
                                 :fullName => "opencast-series-dc-language",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :description,
                                 :fullName => "opencast-series-dc-description",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :rightsHolder,
                                 :fullName => "opencast-series-dc-rightsholder",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :license,
                                 :fullName => "opencast-series-dc-license",
                                 :fallback => nil})
  dc_metadata_definition.push( { :symbol   => :publisher,
                                 :fullName => "opencast-series-dc-publisher",
                                 :fallback => nil})
  return dc_metadata_definition
end

#
# Parses dublincore-relevant information from the metadata
# Contains the definitions for metadata-field-names
# Casts metadata keys to LOWERCASE
#
# metadata: hash (string => string)
#
# return hash (symbol => object)
#
def parseDcMetadata(metadata, dc_metadata_definition)
  dc_data = {}

  dc_metadata_definition.each do |definition|
    dc_data[definition[:symbol]] = parseMetadataFieldOrFallback(metadata, definition[:fullName], definition[:fallback])
    # StudIP - Legacy
    if definition[:symbol] === :isPartOf
      dc_data[:isPartOf] = metadata["opencast-series-id"] if dc_data[:isPartOf].to_s.empty?
    end
  end

  return dc_data
end

#
# Returns the metadata tags defined for user access list
#
# return: hash
#
def getAclMetadataDefinition()
  return {:readRoles => "opencast-acl-read-roles",
          :writeRoles => "opencast-acl-write-roles",
          :userIds => "opencast-acl-user-id"}
end

#
# Returns the metadata tags defined for series access list
#
# return: hash
#
def getSeriesAclMetadataDefinition()
  return {:readRoles => "opencast-series-acl-read-roles",
          :writeRoles => "opencast-series-acl-write-roles",
          :userIds => "opencast-series-acl-user-id"}
end

#
# Parses acl-relevant information from the metadata
#
# metadata: hash (string => string)
#
# return array of hash (symbol => string, symbol => string)
#
def parseAclMetadata(metadata, acl_metadata_definition)
  acl_data = []

  # Read from global, configured-by-user variable
  $defaultRolesWithReadPerm.to_s.split(",").each do |role|
    acl_data.push( { :user => role, :permission => "read" } )
  end
  $defaultRolesWithWritePerm.to_s.split(",").each do |role|
    acl_data.push( { :user => role, :permission => "write" } )
  end

  # Read from Metadata
  metadata[acl_metadata_definition[:readRoles]].to_s.split(",").each do |role|
    acl_data.push( { :user => role, :permission => "read" } )
  end
  metadata[acl_metadata_definition[:writeRoles]].to_s.split(",").each do |role|
    acl_data.push( { :user => role, :permission => "write" } )
  end

  metadata[acl_metadata_definition[:userIds]].to_s.split(",").each do |userId|
    acl_data.push( { :user => "ROLE_USER_#{userId}", :permission => "read" } )
    acl_data.push( { :user => "ROLE_USER_#{userId}", :permission => "write" } )
  end

  return acl_data
end

#
# Creates a xml using the given role information
#
# roles: array of hash (symbol => string, symbol => string), containing user role and permission
#
# returns: string, the xml
#
def createAcl(roles)
  header = Nokogiri::XML('<?xml version = "1.0" encoding = "UTF-8" standalone ="yes"?>')
  builder = Nokogiri::XML::Builder.with(header) do |xml|
    xml.Policy('PolicyId' => 'mediapackage-1',
    'RuleCombiningAlgId' => 'urn:oasis:names:tc:xacml:1.0:rule-combining-algorithm:permit-overrides',
    'Version' => '2.0',
    'xmlns' => 'urn:oasis:names:tc:xacml:2.0:policy:schema:os') {
      roles.each do |role|
        xml.Rule('RuleId' => "#{role[:user]}_#{role[:permission]}_Permit", 'Effect' => 'Permit') {
          xml.Target {
            xml.Actions {
              xml.Action {
                xml.ActionMatch('MatchId' => 'urn:oasis:names:tc:xacml:1.0:function:string-equal') {
                  xml.AttributeValue('DataType' => 'http://www.w3.org/2001/XMLSchema#string') { xml.text(role[:permission]) }
                  xml.ActionAttributeDesignator('AttributeId' => 'urn:oasis:names:tc:xacml:1.0:action:action-id',
                  'DataType' => 'http://www.w3.org/2001/XMLSchema#string')
                }
              }
            }
          }
          xml.Condition{
            xml.Apply('FunctionId' => 'urn:oasis:names:tc:xacml:1.0:function:string-is-in') {
              xml.AttributeValue('DataType' => 'http://www.w3.org/2001/XMLSchema#string') { xml.text(role[:user]) }
              xml.SubjectAttributeDesignator('AttributeId' => 'urn:oasis:names:tc:xacml:2.0:subject:role',
              'DataType' => 'http://www.w3.org/2001/XMLSchema#string')
            }
          }
        }
      end
    }
  end

  return builder.to_xml
end

#
# Parses the text-content of shared notes html file into a string and returns it
#
# path: string, path to shared notes file
#
# return: html text-content as a string
#
def sharedNotesToString(path)
  if (File.file?(File.join(path, "notes.html")))
    doc = File.open(File.join(path, "notes.html")) { |f| Nokogiri::HTML(f) }
    if doc.at('body')
      return doc.at('body').content.to_s
    else
      BigBlueButton.logger.warn(" Shared notes has no body tag, returning empty string instead.")
      return ""
    end
  else
    return ""
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

  # Delete all raw recording data
  # TODO: Find a way to outsource this into a script that runs after all post_archive scripts have run successfully
  system('sudo', 'bbb-record', '--delete', "#{meeting_id}") || raise('Failed to delete local recording')
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
ACL_PATH = File.join(TMP_PATH, "acl.xml")

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
  BigBlueButton.logger.error(": NO EVENTS.XML! Nothing to parse, aborting...")
  exit 1
end

# Get conference start and end timestamps in ms
real_start_time, real_end_time = getRealStartEndTimes(doc)
# Get screen share start timestamps
deskshareStart = parseTimeStamps(doc, 'StartWebRTCDesktopShareEvent', deskshareStart)
# Get webcam share start timestamps
webcamStart = parseTimeStamps(doc, 'StartWebRTCShareEvent', webcamStart)
# Get audio recording start timestamps
audioStart = parseTimeStamps(doc, 'StartRecordingEvent', audioStart)
# Get cut marks
recordingStart, recordingStop = parseTimeStampsRecording(doc, 'RecordStatusEvent', recordingStart, recordingStop, real_end_time)
# Get presentation slide start stamps
presentationSlidesStart = parseTimeStampsPresentation(doc, 'SharePresentationEvent', presentationSlidesStart) # Grab a timestamp for the beginning
presentationSlidesStart = parseTimeStampsPresentation(doc, 'GotoSlideEvent', presentationSlidesStart) # Grab timestamps from Goto events

# Opencasts addPartialTrack cannot handle files without a duration,
# therefore images need to be converted to videos.
presentationSlidesStart = convertSlidesToVideo(presentationSlidesStart)

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
# Exception: Once Opencast can handle multiple webcam files, this can be replaced by a collectFileInformation call
if (Dir.exist?(VIDEO_PATH))
  Dir.foreach(VIDEO_PATH) do |filename|
    next if File.directory?(filename)
    tracks.push( { "flavor": 'presenter/source',
                   "startTime": (webcamStart.detect { |i| i["filename"] == filename }["timestamp"]) - real_start_time,
                   "path": File.join(VIDEO_PATH, filename)
                 } )
    break   # Stop after first iteration to only send first webcam file found. TODO: Teach Opencast to deal with webcam files
  end
end
# Add audio tracks (Likely to be only one track)
tracks = collectFileInformation(AUDIO_PATH, tracks, 'presentation/source', audioStart, real_start_time)
# Add screen share tracks
tracks = collectFileInformation(DESKSHARE_PATH, tracks, 'presentation/source', deskshareStart, real_start_time)
# Add the previously generated tracks for presentation slides
# Use the converted files stored in tmp!
presentationSlidesStart.each do |startItem|
  tracks.push ( { "flavor": 'presentation/source',
                  "startTime": startItem["timestamp"] - real_start_time,
                  "path": File.join(TMP_PATH, startItem["presentationName"], "svgs", startItem["filename"])
              } )
end

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
dc_data = parseDcMetadata(meeting_metadata, getDcMetadataDefinition(meeting_metadata, recordingStart.first, recordingStop.last))
dublincore = createDublincore(dc_data)
BigBlueButton.logger.info( "Dublincore: \n" + dublincore.to_s)

# Create Json containing cutting marks at path
createCuttingMarksJSONAtPath(CUTTING_JSON_PATH, recordingStart, recordingStop, real_start_time, real_end_time)

# Create ACLs at path
aclData = parseAclMetadata(meeting_metadata, getAclMetadataDefinition())
if (!aclData.nil? && !aclData.empty?)
  File.write(ACL_PATH, createAcl(parseAclMetadata(meeting_metadata, getAclMetadataDefinition())))
end


# Create series if it does not exist
# If we got a seriesId (from which metadata?)
createSeriesId = meeting_metadata["opencast-dc-ispartof"]
if ($createNewSeriesIfItDoesNotYetExist && !createSeriesId.to_s.empty?)
  BigBlueButton.logger.info( "Creating a new series...")
  # GET does series exists. Webrequest will fail if it does not exist.
  seriesExists = false
  seriesFromOc = requestIngestAPI(:get, '/series/allSeriesIdTitle.json', DEFAULT_REQUEST_TIMEOUT, {})
  begin
    seriesFromOc = JSON.parse(seriesFromOc)
    seriesFromOc["series"].each do |serie|
      if (serie["identifier"] === createSeriesId)
        seriesExists = true
      end
    end
    if (!seriesExists)
      BigBlueButton.logger.info( "Create a new series with ID " + createSeriesId)
      # Create Series-DC
      seriesDcData = parseDcMetadata(meeting_metadata, getSeriesDcMetadataDefinition(meeting_metadata, real_start_time))
      seriesDublincore = createDublincore(seriesDcData)
      # Create Series-ACL
      seriesAcl = createAcl(parseAclMetadata(meeting_metadata, getSeriesAclMetadataDefinition()))

      requestIngestAPI(:post, '/series/', DEFAULT_REQUEST_TIMEOUT, 
      { :series => seriesDublincore,
        :acl => seriesAcl,
        :override => false})
    end
  rescue JSON::ParserError  => e
    BigBlueButton.logger.warn(" Could not parse series JSON, Exception #{e}")
  end    
end

#
# Create a mediapackage and ingest it
#

# Create Mediapackage
uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
if !dc_data[:identifier].to_s.empty? && uuid_regex.match?(dc_data[:identifier].to_s.downcase)
  mediapackage = requestIngestAPI(:put, '/ingest/createMediaPackageWithID/' + dc_data[:identifier], DEFAULT_REQUEST_TIMEOUT,{})
else
  if !dc_data[:identifier].to_s.empty? && !uuid_regex.match?(dc_data[:identifier].to_s.downcase)
    BigBlueButton.logger.warn(" The given identifier #{dc_data[:identifier]} is not a valid UUID. Using generated UUID instead.")
  end
  mediapackage = requestIngestAPI(:get, '/ingest/createMediaPackage', DEFAULT_REQUEST_TIMEOUT, {})
end
BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
# Add Partial Track
tracks.each do |track|
  BigBlueButton.logger.info( "Track: " + track.to_s)
  mediapackage = requestIngestAPI(:post, '/ingest/addPartialTrack', DEFAULT_REQUEST_TIMEOUT,
                  { :flavor => track[:flavor],
                    :startTime => track[:startTime],
                    :mediaPackage => mediapackage,
                    :body => File.open(track[:path], 'rb') })
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
end
# Add dublincore
mediapackage = requestIngestAPI(:post, '/ingest/addDCCatalog', DEFAULT_REQUEST_TIMEOUT,
                {:mediaPackage => mediapackage,
                 :dublinCore => dublincore })
BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
# Add cutting marks
mediapackage = requestIngestAPI(:post, '/ingest/addCatalog', DEFAULT_REQUEST_TIMEOUT,
                {:mediaPackage => mediapackage,
                 :flavor => CUTTING_MARKS_FLAVOR,
                 :body => File.open(CUTTING_JSON_PATH, 'rb')})
                 #:body => File.open(File.join(archived_files, "cutting.json"), 'rb')})

BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
# Add ACL
if (File.file?(ACL_PATH))
  mediapackage = requestIngestAPI(:post, '/ingest/addAttachment', DEFAULT_REQUEST_TIMEOUT,
                  {:mediaPackage => mediapackage,
                  :flavor => "security/xacml+episode",
                  :body => File.open(ACL_PATH, 'rb') })
  BigBlueButton.logger.info( "Mediapackage: \n" + mediapackage)
else
  BigBlueButton.logger.info( "No ACL found, skipping adding ACL.")
end               
# Ingest and start workflow
response = requestIngestAPI(:post, '/ingest/ingest/' + $oc_workflow, START_WORKFLOW_REQUEST_TIMEOUT,
                { :mediaPackage => mediapackage })
BigBlueButton.logger.info( response)

### Exit gracefully
cleanup(TMP_PATH, meeting_id)
exit 0
