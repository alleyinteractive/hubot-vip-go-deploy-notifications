# Description:
#   Notify rooms about code deployments on VIP Go.
#
# Dependencies:
#   None
#
# Configuration:
#   Requires the VIP team to set up the webhook. This endpoint is:
#
#   http://{your hubot domain}/hubot/vip-go-deployment
#
# Commands:
#   hubot notify about domain.com deploys
#   hubot don't notify this room about domain.com deploys
#   hubot don't notify some_other_room about domain.com deploys
#
# Author:
#   mboynes

class VipGoNotifier
  constructor: (@robot) ->
    @notifications = {}
    @robot.brain.on 'loaded', =>
      if @robot.brain.data.vip_go_notifications?
        @notifications = @robot.brain.data.vip_go_notifications

  save: ->
    @robot.brain.data.vip_go_notifications = @notifications

  addNotification: (room, domain) ->
    @notifications[ domain ] ||= []
    @notifications[ domain ].push room
    @save()

  removeNotification: (room, domain) ->
    if @notifications[ domain ]
      for mappedRoom, i in @notifications[ domain ]
        if room is mappedRoom
          @notifications[ domain ].splice i, 1
          delete @notifications[ domain ] unless @notifications[ domain ].length
          @save()
          return true
    return false

  notificationsForDomain: (domain) ->
    if @notifications[ domain ]
      return @notifications[ domain ]
    return []

  toJson: ->
    JSON.stringify @notifications

module.exports = (robot) ->
  notifier = new VipGoNotifier robot

  robot.respond /notify(?: this room)? about ([^\s]+) deploys/i, (msg) ->
    domain = msg.match[1].replace /^(?:https?:\/\/)?([^\/]+)\/?$/i, '$1'
    notifier.addNotification msg.message.user.room, domain
    msg.send "I will notify this room of deployments for #{domain}"

  robot.respond /don't notify (.*?) about ([^\s]+) deploys/i, (msg) ->
    domain = msg.match[2].replace /^(?:https?:\/\/)?([^\/]+)\/?$/i, '$1'
    if 'this room' is msg.match[1]
      msg.match[1] = msg.message.user.room

    if notifier.removeNotification msg.match[1], domain
      msg.send "I will no longer notify #{msg.match[1]} of deployments for #{domain}"
    else
      msg.send "I could not find any deployment notifications for #{domain} in #{msg.match[1]}"

  robot.respond /list deployment notifications/i, (msg) ->
    msg.send notifier.toJson()

  # Send notifications for deployments
  robot.router.post '/hubot/vip-go-deployment', (req, res) ->
    if req.body.domain
      sha = req.body.sha.slice 0, 7
      notifications = notifier.notificationsForDomain req.body.domain
      for room, i in notifications
        if robot.adapter.customMessage
          robot.adapter.customMessage
            channel: room
            username: robot.name
            attachments:
              "fallback": ":rocket: VIP deployed https://github.com/#{req.body.repo}/commit/#{req.body.sha} to #{req.body.domain}"
              "title": "#{sha} deployed"
              "title_link": "https://github.com/#{req.body.repo}/commit/#{req.body.sha}"
              "text": ":rocket: VIP deployed #{sha} to #{req.body.domain}"
              "color": "good"
        else
          robot.messageRoom room, ":rocket: VIP deployed https://github.com/#{req.body.repo}/commit/#{req.body.sha} to #{req.body.domain}"
    else
      console.log "Invalid POST to VIP Go Deployment Notifier"

    res.send 'OK'
