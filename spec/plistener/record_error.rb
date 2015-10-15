require 'spec_helper'

describe 'Plistener#record_error' do
  include_context "fresh"

  it "records an error" do
    # make an error
    error = begin
      raise "here i am!"
    rescue Exception => e
      e
    end

    # do the record
    plnr.record_error FILEPATH, 'modified', error


  end
end # Plistener#record_error
