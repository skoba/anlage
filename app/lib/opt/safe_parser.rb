module Opt
  # Raised when an uploaded OPT contains a DOCTYPE declaration. Legitimate
  # OPT exports never declare one; rejecting it outright before Nokogiri
  # ever sees it is the simplest complete defense against XXE (entity
  # expansion attacks are impossible without a DTD to declare the entity
  # in), and does not depend on the parse-time defaults of whichever
  # libxml2 happens to be linked.
  class UnsafeTemplate < StandardError; end

  # XXE-safe wrapper around OpenehrRails::Opt.parse. See UnsafeTemplate.
  class SafeParser
    DOCTYPE_PATTERN = /<!DOCTYPE/i

    def self.parse(source_xml)
      if source_xml.to_s.b.match?(DOCTYPE_PATTERN)
        raise UnsafeTemplate, "DOCTYPE declarations are not allowed in OPT uploads"
      end

      OpenehrRails::Opt.parse(source_xml)
    end
  end
end
