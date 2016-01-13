# Description:
#   Retrieves data about devices and services on Server Density.
#   https://www.serverdensity.io
#
# Dependencies:
#   None
#
# Configuration:
#   API_KEY - Key created in the security tab on the user's settings
#   ACCOUNT_NAME - First part of Server Density url THISBIT.serverdensity.io
#
# Commands:
#   hubot status of item_name ('long') - Reply back with load average and memory
#                                      usage stats of the item.
#                                      Add 'long' to add disk and network
#
#   hubot triggered alerts - Reply back with a complete list of triggered alert
#
#   hubot alerts for item_name - Reply back with the triggered alerts for the
#                                named item
#
#   hubot url for item_name ('graphs', 'alerts', 'plugins', 'snapshot')
#                              - Reply back with the url to item. Default is
#                                returns /overview.
#

# Author:
#   chrishannam

module.exports = (robot) ->

    API_KEY = "API_KEY" # change me!
    ACCOUNT_NAME = "ACCOUNT_NAME" # change me!
    ACCOUNT_URL = "https://#{ACCOUNT_NAME}.serverdensity.io"
    API_BASE_URL = "https://api.serverdensity.io"
    TOKEN_PARAM = "?token=#{API_KEY}"
    ALERTS_TRIGGERED_URL = "#{API_BASE_URL}/alerts/triggered?token=#{API_KEY}&closed=false"
    ALERTS_CONFIGS_URL = "#{API_BASE_URL}/alerts/configs/"
    METRICS_GRAPHING_URL = "#{API_BASE_URL}/metrics/graphs"
    FETCH_DEVICE_FROM_INVENTORY_URL = "#{API_BASE_URL}/inventory/devices/"
    FETCH_SERVICE_FROM_INVENTORY_URL = "#{API_BASE_URL}/inventory/services/"

    FETCH_DEVICE_FROM_INVENTORY_BY_NAME_URL = "#{API_BASE_URL}/inventory/devices/"
    FETCH_SERVICE_FROM_INVENTORY_BY_NAME_URL = "#{API_BASE_URL}/inventory/services/"

    FETCH_FROM_INVENTORY_URL = "#{API_BASE_URL}/inventory/devices/"
    FETCH_FROM_INVENTORY_BY_NAME_URL = "#{API_BASE_URL}/inventory/devices/"

    MS_PER_MINUTE = 60000

    fetchURL = (msg, url, callback) ->
        msg.http(url)
            .get() (error, response, body) ->
                callback(JSON.parse(body))

    fetchDevice = (msg, itemName, callback) ->
        devicesUrl = FETCH_DEVICE_FROM_INVENTORY_BY_NAME_URL + TOKEN_PARAM + "&filter={\"name\":\"#{itemName}\"}"
        msg.http(devicesUrl)
            .get() (error, response, body) ->
                if error
                    robot.logger.error "Error when fetching device."
                    robot.logger.error body
                    callback(undefined)

                devicesJSON = JSON.parse(body)

                if devicesJSON.length != 0
                    callback(devicesJSON[0])
                else
                    callback(false)

    fetchService = (msg, itemName, callback) ->
        servicesUrl = FETCH_SERVICE_FROM_INVENTORY_BY_NAME_URL + TOKEN_PARAM + "&filter={\"name\":\"#{itemName}\"}"
        msg.http(servicesUrl)
            .get() (error, response, body) ->
                if error
                    robot.logger.error "Error when fetching service."
                    robot.logger.error body
                    callback(undefined)

                servicesJSON = JSON.parse(body)

                if servicesJSON.length != 0
                    callback(servicesJSON[0])
                else
                    callback(false)

    robot.respond /triggered alerts$/i, (msg) ->
        msg.http(ALERTS_TRIGGERED_URL)
            .get() (error, response, body) ->
                # passes back the complete reponse
                alerts = JSON.parse(body)
                triggered = alerts.length

                msg.send "Currently " + triggered.toString() + " triggered alerts!"

                if alerts.length == 0
                    msg.send (awyeah)

                for item, index in alerts
                    ((item)->
                        itemId = item.config.subjectId
                        if item.config.subjectType == "deviceGroup" or item.config.subjectType == "serviceGroup"
                            replyString = itemId + ' Group -> ' + item.config.fullName
                            if item.config.subjectType == "deviceGroup"
                                replyString += " #{ACCOUNT_URL}/devices/groups/" + itemId
                            else
                                replyString += " #{ACCOUNT_URL}/services/groups/" + itemId
                            msg.send replyString
                        else
                            msg.http(FETCH_DEVICE_FROM_INVENTORY_URL + itemId + TOKEN_PARAM)
                                .get() (error, response, body) ->
                                    device = JSON.parse(body)
                                    if device.length != 0
                                        msg.send device.name + ' -> ' + item.config.fullName + " #{ACCOUNT_URL}/devices/" + device._id + "/alerting"
                                    else
                                        msg.http(FETCH_SERVICE_FROM_INVENTORY_URL + itemId + TOKEN_PARAM)
                                            .get() (error, response, body) ->
                                                deviceDetails = JSON.parse(body)
                                                msg.send deviceDetails.name + ' -> ' + item.config.fullName + " #{ACCOUNT_URL}/devices/" + device._id + "/alerting"
                    ) item

    robot.respond /alerts for (.*)/i, (msg) ->
        serverName = msg.match[1]

        fetchDevice msg, serverName, (device) ->

            if device != false
                msg.http(ALERTS_CONFIGS_URL + device.id + TOKEN_PARAM + "&subjectType=device")
                .get() (error, response, body) ->

                    msg.send "Open Alerts for " + serverName

                    if not body
                        msg.send "None! (awyeah)"
                        return

                    configs = JSON.parse(body)
                    alerts = false

                    if configs.length == 0
                        msg.send "None! (awyeah)"
                        return

                    for config, index in configs
                        ((config)->
                            if config.open
                                output = config.section

                                if config.field
                                    output += ' -> '+ config.field

                                if config.subject
                                    output += ' -> '+ config.subject

                                if config.value
                                    output += ' ' + config.comparison + ' ' + config.value

                                msg.send output
                                alerts = true
                        ) config


            else
                fetchService msg, serverName, (service) ->
                    msg.http(ALERTS_CONFIGS_URL + service.id + TOKEN_PARAM + "&subjectType=service")
                    .get() (error, response, body) ->

                        msg.send "Open Alerts for " + serverName
                        if not body
                            msg.send "None! (awyeah)"
                            return
                        configs = JSON.parse(body)
                        alerts = false

                        for config, index in configs
                            ((config)->
                                if config.open
                                    output = config.section

                                    if config.field
                                        output += ' -> '+ config.field

                                    if config.subject
                                        output += ' -> '+ config.subject

                                    if config.value
                                        output += ' ' + config.comparison + ' ' + config.value

                                    msg.send output
                                    alerts = true
                            ) config

                        if not alerts
                            msg.send "None! (awyeah)"

    robot.respond /url for (.*)/i, (msg) ->
        stringToSearch = msg.match[1]
        stringToSearchSplit = stringToSearch.split(" ")

        overview = false
        type = ""
        if stringToSearchSplit[stringToSearchSplit.length - 1] not in ['graphs', 'alerts', 'plugins', 'snapshot']
            overview = true
        else
            type = stringToSearchSplit[stringToSearchSplit.length - 1]
            stringToSearchSplit.pop()

        serverName = stringToSearchSplit.join(" ")

        # try a device first
        fetchDevice msg, serverName, (device) ->
            if device != false
                if type == "graphs"
                    msg.reply "#{ACCOUNT_URL}/devices/" + device._id + "/monitoring"
                else if type == "alerts"
                    msg.reply "#{ACCOUNT_URL}/devices/" + device._id + "/alerting"
                else if type == "plugins"
                    msg.reply "#{ACCOUNT_URL}/devices/" + device._id + "/plugins"
                else if type == "snapshot"
                    msg.reply "#{ACCOUNT_URL}/devices/" + device._id + "/snapshot"
                else
                    msg.reply "#{ACCOUNT_URL}/devices/" + device._id + "/overview"
            else
                fetchService msg, serverName, (service) ->
                    if service == false
                        msg.reply "Unable to find item, maybe check the case?"
                    else if type == "graphs"
                        msg.reply "#{ACCOUNT_URL}/services/" + service._id + "/monitoring"
                    else if type == "alerts"
                        msg.reply "#{ACCOUNT_URL}/services/" + service._id + "/alerting"
                    else if type == "plugins"
                        msg.reply "#{ACCOUNT_URL}/services/" + service._id + "/plugins"
                    else if type == "snapshot"
                        msg.reply "#{ACCOUNT_URL}/services/" + service._id + "/snapshot"
                    else
                        msg.reply "#{ACCOUNT_URL}/services/" + service._id + "/overview"

    robot.respond /status for (.*)/i, (msg) ->
        stringToSearch = msg.match[1]
        stringToSearchSplit = stringToSearch.split(" ")

        overview = false
        if stringToSearchSplit[stringToSearchSplit.length - 1] in ['long']
            overview = true
            stringToSearchSplit.pop()

        serverName = stringToSearchSplit.join(" ")

        fetchDevice msg, serverName, (device) ->
                # passes back the complete reponse
                robot.logger.error device
                if device != false
                    ((device)->
                        myEndDateTime = new Date()
                        # give a range in case we hit near a minute mark
                        durationInMinutes = 3
                        myStartDate = new Date(myEndDateTime - durationInMinutes * MS_PER_MINUTE);

                        if overview
                            filter = '{"loadAvrg":"all","memory":{"memSwapUsed":"all","memPhysUsed":"all"},"diskUsage":"all","networkTraffic":["rxMBitS","txMBitS"]}'
                        else
                            filter = '{"loadAvrg":"all","memory":{"memSwapUsed":"all","memPhysUsed":"all"}}'

                        msg.http(METRICS_GRAPHING_URL + '/' + device._id + TOKEN_PARAM + "&start=#{myStartDate.toISOString()}&end=#{myEndDateTime.toISOString()}&filter=#{filter}")
                            .get() (error, response, body) ->
                                metrics = JSON.parse(body)

                                for metric, index in metrics
                                    ((metric)->
                                        msg.send "Last reading for: " + metric.name
                                        for measure, ind in metric.tree
                                            ((measure, metric)->
                                                if measure.data and measure.data.length == 0
                                                    msg.send "No data."
                                                else if measure.data
                                                    if measure.name != metric.name
                                                        msg.send measure.name + ' -> ' + measure.data[measure.data.length - 1].y
                                                    else
                                                        msg.send measure.data[measure.data.length - 1].y
                                                # deal with 2 deep
                                                else
                                                    msg.send measure.name
                                                    for subMeasure, ind in measure.tree
                                                        ((subMeasure)->
                                                            #msg.send subMeasure.data
                                                            if subMeasure.name == metric.name
                                                                msg.send subMeasure.data[subMeasure.data.length - 1].y
                                                            else
                                                                msg.send subMeasure.name + ' -> ' + subMeasure.data[subMeasure.data.length - 1].y
                                                        ) subMeasure
                                            ) measure, metric
                                    ) metric
                    ) device
                else
                    fetchService msg, serverName, (service) ->
                        if service == false
                            msg.reply "Unable to find item, maybe check the case?"

                        else
                            ((service)->
                                myEndDateTime = new Date()
                                # give a range in case we hit near a minute mark
                                durationInMinutes = 20
                                myStartDate = new Date(myEndDateTime - durationInMinutes * MS_PER_MINUTE);

                                filter = '{"time":"all"}'

                                msg.http(METRICS_GRAPHING_URL + '/' + service._id + TOKEN_PARAM + "&start=#{myStartDate.toISOString()}&end=#{myEndDateTime.toISOString()}&filter=#{filter}")
                                    .get() (error, response, body) ->
                                        metrics = JSON.parse(body)

                                        for metric, index in metrics
                                            ((metric)->
                                                msg.send "Last reading for: " + metric.name
                                                for measure, ind in metric.tree
                                                    ((measure)->
                                                        if measure.data.length != 0
                                                            msg.send measure.name + ' -> ' + measure.data[measure.data.length - 1].y
                                                            return
                                                        else
                                                            msg.send "No data."
                                                    ) measure
                                            ) metric
                            ) service
