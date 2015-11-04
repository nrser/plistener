class Plistener
  VERSION = "0.0.1.dev"

  def self.readme section
    path = File.expand_path File.join('..', '..', '..', 'README.md'), __FILE__
    contents = File.read path
    contents.
      partition(/\<\!\-\-\ #{ section }\ \-\-\>\s*/).
      last.
      partition(/\s*\<\!\-\-\ \/#{ section }\ \-\-\>/).
      first
  end
end
