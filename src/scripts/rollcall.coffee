# Description:
#   A Hubot plugin for the Rollcall service at https://gorollcall.com
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_ROLLCALL_WEBHOOK - get this URL from https://my.gorollcall.com/
#
#
# Commands:
#   rollcall i am <rollcall email address> - map your user to your Rollcall account (required!)
#   rollcall search <entity search terms e.g. owner/project#term> - search for issuses or projects for use in your status update
#   rollcall working on <status update> - update your status on Rollcall
#   rollcall post <status update> - alternative syntax for posting a status update
#
# URL:
#   POST /hubot/rollcall
#
# Author:
#   sujal

util = require('util')

send_command_to_rollcall = (msg, command, matched_data, callback) ->

  remote_username = msg.message.user.id
  rollcall_account = null
  if command == "map"
    rollcall_account = matched_data
  else
    rollcall_account = msg.message.user.rollcallAccount

  # console.log rollcall_account

  return callback(new Error("I don't know your username on Rollcall. Tell me who you are.")) unless rollcall_account?

  post_body = {
    command: command,
    from: rollcall_account,
    remote_username: remote_username
  }

  if (command != "map")
    post_body["body"] = matched_data

  # console.log post_body

  msg.http(process.env.HUBOT_ROLLCALL_WEBHOOK)
    .headers(Accept: 'application/json', "Content-Type": "application/json")
    .post(JSON.stringify(post_body)) (err, res, body) ->

      return callback(err) if err?

      r = JSON.parse(body)

      switch res.statusCode
        when 200
          return callback(null, r)
        when 404
          return callback(new Error("404 Received: #{r?.meta?.text}"), r)
        when 403
          return callback(new Error("Error: #{r?.meta?.text}"), r)
        else
          return callback(new Error("Unknown Error: #{r?.meta?.text}"), r)



module.exports = (robot) ->
  if process.env.HUBOT_ROLLCALL_WEBHOOK

    robot.hear /^rollcall\s+i\s+am\s+(.*)$/i, (msg) ->
      rollcall_email = msg.match[1]
      msg.message.user.rollcallAccount = rollcall_email
      send_command_to_rollcall msg, "map", rollcall_email, (err, response) ->
        return robot.reply "Error mapping user: #{err.message}" if err?
        msg.reply "You are #{rollcall_email} on Rollcall."


    robot.hear /^rollcall\s+search\s+(.*)$/i, (msg) ->
      rollcall_body = msg.match[1]
      send_command_to_rollcall msg, "search", rollcall_body, (err, response) ->
        return msg.send "Error searching Rollcall: #{err.message}" if err?

        output = null
        result_count = response.organization?.matching_entities?.length || 0
        if (result_count == 0)
          output = "Found 0 results for #{rollcall_body}"
        else
          output = "Found #{result_count} results for #{rollcall_body}:\n\n"
          for entity in response.organization.matching_entities
            output += "#{entity.entity_key} - #{entity.name}\n"

        msg.reply output


    robot.hear /^rollcall\s+working\s+on\s+(.*)$/i, (msg) ->
      rollcall_body = msg.match[1]
      send_command_to_rollcall msg, "post", rollcall_body, (err, response) ->
        return msg.send "Error updating Rollcall: #{err.message}" if err?
        msg.reply "✓"

    robot.hear /^rollcall\s+post\s+(.*)$/i, (msg) ->
      rollcall_body = msg.match[1]
      send_command_to_rollcall msg, "post", rollcall_body, (err, response) ->
        return msg.send "Error updating Rollcall: #{err.message}" if err?
        msg.reply "✓"

    robot.hear /^rollcall\s+who\s+am\s+i\s*$/i, (msg) ->
      user = msg.message.user
      if user.rollcallAccount
        msg.reply "You are known as #{user.rollcallAccount} on Rollcall"
      else
        msg.reply "I don't know who you are. Tell rollcall who you are."

    robot.router.post "/hubot/rollcall", (req, res) ->

      res.end JSON.stringify {
        received: true #some client have problems with and empty response
      }

      try
        payload = JSON.parse req.body

        robot.send "[#{payload.status.organization.domain}] #{payload.status.body} - #{payload.status.user.name}"

      catch error
        console.log "rollcall hook error: #{error}. Payload: #{req.body.payload}"



