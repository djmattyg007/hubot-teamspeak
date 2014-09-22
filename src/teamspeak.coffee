# Hubot dependencies
Robot = require '../../hubot/src/robot'
Adapter = require '../../hubot/src/adapter'
{TextMessage, EnterMessage, LeaveMessage} = require '../../hubot/src/message'

# teamspeak library
TeamSpeakClient = require 'node-teamspeak-fix'
util = require 'util'
fs = require 'fs'

class TeamSpeakAdapter extends Adapter
    send: (envelope, strings...) ->
        console.log "Sending"
        for str in strings
            @message envelope.user, envelope.room, str

    reply: (envelope, strings...) ->
        console.log "Replying"
        for str in strings
            @message envelope.user, envelope.room, str

    message: (client, room, message) ->
        self = @
        console.log "Firing sendtextmessage"
        target = client.clid if room == 1
        target = client.cid if room == 2
        target = self.config.serverid if room == 3
        self.bot.send "sendtextmessage", {targetmode: room, target: target, msg: message}, []
        console.log "Done firing sendtextmessage"

    getUserFromName: (name) ->
        return @robot.brain.userForName(name) if @robot.brain?.userForName?

        return @userForName name

    getUserFromId: (id) ->
        return @robot.brain.userForId(id) if @robot.brain?.userForId?

        return @userForId id

    createUser: (client) ->
        user = @getUserFromName client.client_nickname
        unless user?
            id = client.client_database_id
            user = @getUserFromId id
            user.name = client.client_nickname
            for key, value of client
                user[key] = client[key]

        user

    checkCanStart: ->
        if not process.env.HUBOT_TEAMSPEAK_CONFIG
            throw new Error("HUBOT_TEAMSPEAK_CONFIG is not defined; try: export HUBOT_TEAMSPEAK_CONFIG='/path/to/some/config.js'")

    loadConfig: (configLocation) ->
        file = fs.readFileSync configLocation, {encoding: 'UTF-8'}
        @config = JSON.parse(file);

    run: ->
        self = @

        do @checkCanStart
        @loadConfig process.env.HUBOT_TEAMSPEAK_CONFIG

        @robot.name = @config.nickname
        bot = new TeamSpeakClient @config.server
        @bot = bot

        do @doLogin

    doLogin: ->
        self = @
        self.bot.send "login", {client_login_name: self.config.username, client_login_password: self.config.password}, [], (err, resp) ->
            self.bot.send "use", {sid: self.config.serverid}, [], ->
                self.bot.send "clientupdate", {client_nickname: self.config.nickname}, []
                do self.doBinds
                self.emit "connected"

    doBinds: ->
        self = @
        self.bot.send "servernotifyregister", {event: "textprivate"}, []
        self.bot.send "servernotifyregister", {event: "textserver"}, []
        self.bot.send "servernotifyregister", {event: "channel", id: 0}, []

        self.bot.send "channellist", {}, [], (err, response) ->
            for channel in response
                self.bot.send "servernotifyregister", {event: "channel", id: channel.cid}, []
                self.bot.send "servernotifyregister", {event: "textchannel", id: channel.cid}, []

        self.bot.on 'connect', (err, response) ->
            if typeof response != "undefined"
                console.log response

        self.bot.on 'error', (err) ->
            console.log "bot error: " + err

        console.log "Binding TextMessage"
        self.bot.on "textmessage", (event) ->
            user = self.getUserFromName event.invokername
            unless user?
                self.bot.send "clientinfo", {clid: event.invokerid}, [], (err, client) ->
                    client.clid = event.invokerid
                    user = self.createUser client
                    self.buildTextMessage user, event.targetmode, event.msg
                    return

            self.buildTextMessage user, event.targetmode, event.msg

    buildTextMessage: (user, target, msgtext) ->
        message = new TextMessage user, msgtext
        message.room = target
        @receive message

    receive: (message) ->
        @robot.receive message

    error: (e) ->
        console.log "There was an error."
        console.log e

exports.use = (robot) ->
    new TeamSpeakAdapter robot
