require 'nokogiri'        #XML-Parser

module OcUtil

  #
  # Raised if a request to Opencast fails
  #
  class RequestError < StandardError; end

  def self.private_module_function(name)   #:nodoc:
    module_function name
    private_class_method name
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
  module_function :parseMetadataFieldOrFallback

  #
  # Helper function for creating xml nodes
  #
  def nokogiriNodeCreator(doc, name, content, attributes = nil)
    new_node = Nokogiri::XML::Node.new(name, doc)
    new_node.content = content
    unless attributes.nil?
      attributes.each do |attribute|
        new_node.set_attribute(attribute[:name], attribute[:value])
      end
    end
    return new_node
  end
  module_function :nokogiriNodeCreator

  #
  # Recursively check if 2 Nokogiri nodes are the same
  # Does not check for attributes
  #
  # node1: The first Nokogiri node
  # node2: The second Nokogori node
  #
  # returns: boolean, true if the nodes are equal
  #
  def sameNodes?(node1, node2, truthArray=[])
    if node1.nil? || node2.nil?
      return false
    end
    if node1.name != node2.name
      return false
    end
    if node1.text != node2.text
            return false
    end
    node1Kids = node1.children
    node2Kids = node2.children
    node1Kids.zip(node2Kids).each do |pair|
      truthArray << sameNodes?(pair[0],pair[1])
    end
    # if every value in the array is true, then the nodes are equal
    return truthArray.all?
  end
  module_function :sameNodes?

  #
  # Sends a web request to Opencast
  #
  # opencast: hash with OC :server, :user and :password
  # method: Http method, symbol (e.g. :get, :post)
  # url: ingest method, string (e.g. '/ingest/addPartialTrack')
  # timeout: seconds until request returns with a timeout, numeric
  # payload: information necessary for the request, hash
  #
  # return: The web request response
  # raises: RequestError if the request fails
  #
  def requestIngestAPI(opencast, method, url, timeout, payload, additionalErrorMessage="")
    begin
      response = RestClient::Request.new(
        :method => method,
        :url => opencast[:server] + url,
        :user => opencast[:user],
        :password => opencast[:password],
        :timeout => timeout,
        :payload => payload
      ).execute
    rescue => e
      message = ["A problem occured for request #{url}: #{e.class}: #{e.message}"]
      message.push(e.http_body.to_s) if e.is_a?(RestClient::Exception)
      message.push(additionalErrorMessage) unless additionalErrorMessage.to_s.empty?
      raise RequestError, message.join("\n")
    ensure
      # Close files passed as request bodies
      payload.each_value { |value| value.close if value.is_a?(File) && !value.closed? } if payload.is_a?(Hash)
    end

    return response
  end
  module_function :requestIngestAPI

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
  module_function :getRealStartEndTimes

end
