require 'spec_helper'

describe GovukMirrorer::Configurer do
  it "should fail if MIRRORER_SITE_ROOT is not set" do
    lambda do
      GovukMirrorer::Configurer.run
    end.should raise_error(GovukMirrorer::Configurer::NoRootUrlSpecifiedError)
  end

  it "should place the site root into the options bucket even though it sucks" do
    ENV["MIRRORER_SITE_ROOT"] = "sausage"
    GovukMirrorer::Configurer.run.should include(:site_root => "sausage" )
  end
end
