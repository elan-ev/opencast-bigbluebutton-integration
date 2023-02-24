require_relative 'oc_util'

require 'rest-client'     #Easier HTTP Requests
require 'date' #The method 'to_datetime'

module OcDublincore

  def self.private_module_function(name)   #:nodoc:
    module_function name
    private_class_method name
  end

  #
  # Creates a definition for metadata, containing symbol, identifier and fallback
  #
  # metadata: hash (string => string)
  # meetingStartTime: time, as a fallback for the "created" metadata-field
  #
  # return: array of hashes
  #
  def getDcMetadataDefinition(metadata, useSharedNotesForDescriptionFallback, passIdentifierAsDcSource,
                              meetingStartTime, meetingEndTime)
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
                                  :fallback => useSharedNotesForDescriptionFallback ?
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
                                  :fallback => (meetingStartTime && meetingEndTime) ?
                                                "start=#{Time.at(meetingStartTime / 1000).to_datetime};
                                                end=#{Time.at(meetingEndTime / 1000).to_datetime};
                                                scheme=W3C-DTF"
                                                : nil})
    dc_metadata_definition.push( { :symbol   => :source,
                                  :fullName => "opencast-dc-source",
                                  :fallback => passIdentifierAsDcSource ?
                                               metadata["opencast-dc-identifier"] : nil })
    return dc_metadata_definition
  end
  module_function :getDcMetadataDefinition

  #
  # Parses dublincore-relevant information from the metadata
  # or inserts a fallback value if applicable
  #
  # Will try to guarantee valid data.
  # To that end, OC API requests may be required.
  #
  # metadata: hash (string => string)
  # useSharedNotesForDescriptionFallback: bool
  # passIdentifierAsDcSource: bool
  # **args:
  # startTime: optional, unixtime. Fallback for the start time of the recording
  # endTime: optional, unixtime. Fallback for the end time of the recording
  # server: optional, string. OC server address
  # user: optional, string. OC user name
  # password: optional, string. OC user password
  #
  # return hash (symbol => object)
  #
  def parseDcMetadata(metadata, getSeriesMetadata=false, useSharedNotesForDescriptionFallback=false, passIdentifierAsDcSource=false, **args)
    # Cast keys to lowercase
    metadata = OcUtil::keysLowerCase(metadata)

    # Get an array of hashes for with key names and fallback values
    dc_metadata_definition = getDcMetadataDefinition(metadata, useSharedNotesForDescriptionFallback,
      passIdentifierAsDcSource, args[:startTime], args[:stopTime])

    # Get values for the given keys, or use fallback values of the key does not exist
    dc_data = {}
    dc_metadata_definition.each do |definition|
      dc_data[definition[:symbol]] = OcUtil::parseMetadataFieldOrFallback(metadata, definition[:fullName], definition[:fallback])
    end

    # A non-empty title is required for a successful ingest
    if dc_data[:title].to_s.empty?
      dc_data[:title] = "Default Title"
    end

    # Avoid using invalid or existing ids (to avoid ingest errors and accidental overwrites)
    dc_data[:identifier] = checkEventIdentifier(dc_data[:identifier], args[:server], args[:user], args[:password])

    return dc_data
  end
  module_function :parseDcMetadata

  #
  # Checks if the given identifier is valid to be used for an Opencast event
  #
  # identifier: string, to be used as the UID for an Opencast event
  #
  # Returns the identifier if it is valid, nil if not
  #
  def checkEventIdentifier(identifier, oc_server, oc_user, oc_password)
    # Check for nil & empty
    if identifier.to_s.empty? || !oc_server || !oc_user || !oc_password
      return nil
    end

    # Check for UUID conformity
    uuid_regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    if !(identifier.to_s.downcase =~ uuid_regex)
      BigBlueButton.logger.info("OC_DUBLINCORE: The given identifier <#{identifier}> is not a valid UUID. Will be using generated UUID instead.")
      return nil
    end

    # Check for existence in Opencast
    existsInOpencast = true
    begin
      response = RestClient::Request.new(
        :method => :get,
        :url => oc_server + "/api/events/" + identifier,
        :user => oc_user,
        :password => oc_password,
      ).execute
    rescue RestClient::Exception => e
      existsInOpencast = false
    end
    if existsInOpencast
      BigBlueButton.logger.info("OC_DUBLINCORE: The given identifier <#{identifier}> already exists within Opencast. Will be using generated UUID instead.")
      return nil
    end

    return identifier
  end
  private_module_function :checkEventIdentifier

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
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:title', dc_data[:title])
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:identifier', dc_data[:identifier])      if dc_data[:identifier]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:creator', dc_data[:creator])            if dc_data[:creator]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:isPartOf', dc_data[:isPartOf])          if dc_data[:isPartOf]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:contributor', dc_data[:contributor])    if dc_data[:contributor]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:subject', dc_data[:subject])            if dc_data[:subject]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:language', dc_data[:language])          if dc_data[:language]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:description', dc_data[:description])    if dc_data[:description]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:spatial', dc_data[:spatial])            if dc_data[:spatial]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:created', dc_data[:created])            if dc_data[:created]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:rightsHolder', dc_data[:rightsHolder])  if dc_data[:rightsHolder]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:license', dc_data[:license])            if dc_data[:license]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:publisher', dc_data[:publisher])        if dc_data[:publisher]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:temporal', dc_data[:temporal],
                                            [{name: "xsi:type", value: "dcterms:Period"}])        if dc_data[:temporal]
    node_set << OcUtil::nokogiriNodeCreator(doc, 'dcterms:source', dc_data[:source])              if dc_data[:source]

    # Add nodes
    doc.root.add_child(node_set)

    # Finalize
    return doc.to_xml
  end
  module_function :createDublincore

  #
  # Creates a definition for metadata, containing symbol, identifier and fallback
  #
  # metadata: hash (string => string)
  #
  # return: array of hashes
  #
  def getSeriesDcMetadataDefinition(metadata)
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
  private_module_function :getSeriesDcMetadataDefinition

  #
  # Parses dublincore-relevant information from the metadata
  # or inserts a fallback value if applicable
  #
  # Will try to guarantee valid data.
  # To that end, OC API requests may be required.
  #
  # metadata: hash (string => string)
  #
  # return hash (symbol => object)
  #
  def parseSeriesDcMetadata(metadata)
    # Get an array of hashes for with key names and fallback values
    dc_metadata_definition = getSeriesDcMetadataDefinition(metadata)

    # Get values for the given keys, or use fallback values of the key does not exist
    dc_data = {}
    dc_metadata_definition.each do |definition|
      dc_data[definition[:symbol]] = OcUtil::parseMetadataFieldOrFallback(metadata, definition[:fullName], definition[:fallback])
    end

    return dc_data
  end
  module_function :parseSeriesDcMetadata

end