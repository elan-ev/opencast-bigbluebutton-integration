require 'nokogiri'        #XML-Parser

module OcUtil

  def self.private_module_function(name)   #:nodoc:
    module_function name
    private_class_method name
  end

  #
  # Helper function: Convert metadata keys to lowercase
  # Transform_Keys is only available from ruby 2.5 onward :(
  #metadata = metadata.transform_keys(&:downcase)
  #
  private def keysLowerCase(oldHash)
    newHash = {}
    oldHash.each do |key, value|
      newHash["#{key.downcase}"] = oldHash[key] #.delete("#{key}")
    end
    return newHash
  end
  module_function :keysLowerCase

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
    node1Attrs = node1.attributes
    node2Attrs = node2.attributes
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
  # Sends a web request to Opencast, using the credentials defined at the top
  #
  # method: Http method, symbol (e.g. :get, :post)
  # url: ingest method, string (e.g. '/ingest/addPartialTrack')
  # timeout: seconds until request returns with a timeout, numeric
  # payload: information necessary for the request, hash
  #
  # return: The web request response
  #
  def requestIngestAPI(server, user, password, method, url, timeout, payload, additionalErrorMessage="")
    begin
      response = RestClient::Request.new(
        :method => method,
        :url => server + url,
        :user => user,
        :password => password,
        :timeout => timeout,
        :payload => payload
      ).execute
    rescue RestClient::Exception => e
      BigBlueButton.logger.error(" A problem occured for request: #{url}")
      BigBlueButton.logger.info( e)
      BigBlueButton.logger.info( e.http_body)
      BigBlueButton.logger.info( additionalErrorMessage)
      exit 1
    rescue => e
      BigBlueButton.logger.error("An unknown problem occured for request: #{url}")
      BigBlueButton.logger.info(e)
      exit 1
    end

    return response
  end
  module_function :requestIngestAPI

end
