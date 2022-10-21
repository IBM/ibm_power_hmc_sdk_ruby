# IBM Power HMC Ruby SDK

Ruby client library to interact with the IBM Hardware Management Console.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ibm_power_hmc'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install ibm_power_hmc

## Usage

### Connection

```ruby
require "ibm_power_hmc"

hc = IbmPowerHmc::Connection.new(
  host: "<hmc host>",
  username: "<hmc user (e.g. hscroot)>",
  password: "<hmc password>",
  validate_ssl: false)
```

### Using the SDK

Retrieving information about the management console itself:

```ruby
hmc = hc.management_console
puts hmc.name
puts hmc.version
```

Retrieving managed systems that are powered on:

```ruby
hc.managed_systems("State==operating")
```

Listing the logical partitions and virtual I/O servers of each managed system:

```ruby
hc.managed_systems.each do |sys|
  puts sys.name
  hc.lpars(sys.uuid).each { |lpar| puts lpar.name }
  hc.vioses(sys.uuid).each { |vios| puts vios.name }
end
```

Retrieving a quick property for a given logical partition:

```ruby
hc.lpar_quick_property(lpar_uuid, "PartitionState")
```

Shutting down a logical partition:

```ruby
hc.poweroff_lpar(lpar_uuid, { "operation" => "shutdown" })
```

Listing serviceable events:

```ruby
puts hc.serviceable_events
```

Processing HMC events:

```ruby
loop do
  hc.next_events.each do |event|
    puts event.type
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/IBM/ibm_power_hmc_sdk_ruby.


## License

This SDK is released under the Apache 2.0 license.
The license's full text can be found in [LICENSE](https://github.com/IBM/ibm_power_hmc_sdk_ruby/blob/master/LICENSE).
