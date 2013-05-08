--Copyright (c) 2007 Neil Richardson (nrich@iinet.net.au)
--
--Permission is hereby granted, free of charge, to any person obtaining a copy 
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights 
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
--copies of the Software, and to permit persons to whom the Software is 
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS 
--IN THE SOFTWARE.

module('AGI', package.seeall)

-- Put all AGI variables in a table and return
local function ReadParse(self, fh)
    local function RealReadParse(agi, fh)
	if not fh then
	    fh = io.stdin
	end

	local env = {}

	for line in fh:lines() do
	    if string.len(line) < 1 then
		break
	    end

	    local k, v = string.match(line, "^agi_(%w+):%s+(.*)$")

	    if k and v then
		env[k] = v
	    end
	end

	self.env = env

	return self.env
    end

    if not self.env then
	return RealReadParse(self, fh)
    end

    return self.env
end

local function Execute(self, command)
    local function execute(agi, command, fh)
	if not fh then 
	    fh = io.stdout
	end

	if not command or not(string.len(command) > 0) then
	    return false
	end

	fh:write(command .. '\n')
	fh:flush()
	return true
    end

    local function ReadResponse(agi, fh)
	if not fh then
	    fh = io.stdin
	end

	local response = fh:read()
	--local response = nil

	if not response or string.len(response) < 1 then
	    return '200 result=-1 (noresponse)'
	end

	return response
    end

    local function CheckResults(agi, response)
	if not response then
	    return false
	end

	agi.last_response = response

	local result = false
	if string.match(response, '^200') then
	    local match = string.match(response, 'result=(-?[%d*#]+)')

	    if match then
		response = match
		agi.last_response = match
	    end
	elseif string.match(response, '\(noresponse\)') then
	    agi.status = 'noresponse' 
	else
	    io.stderr:write('Unexpected result\n')
	end

	return result
    end

    -- just in case...
    self:ReadParse()

    execute(self, command)
    local res = ReadResponse(self)
    local ret = CheckResults(self, res)

    if ret and ret == -1 and not self.hungup then
	self.hungup = true
	self:Callback(ret)
    end

    return ret
end

-- Set function to execute when call is hungup or function returns error.
local function SetCallback(self, callback)
    if not callback or type(callback) ~= 'function' then
	error('Invalid callback tyrying to be set')
    end

    self.callback = callback
end

local function Callback(self, result)
    if self.callback and type(callback) == 'function' then
	self.callback(result)
    end
end

-- Answers channel if not already in answer state
local function Answer(self)
    return Execute(self, 'ANSWER')
end

--Returns the status of the specified channel.  If no channel name is given the
--returns the status of the current channel.
--
-- Returns:
--  -1 Channel hungup or error
--  0 Channel is down and available
--  1 Channel is down, but reserved
--  2 Channel is off hook
--  3 Digits (or equivalent) have been dialed
--  4 Line is ringing
--  5 Remote end is ringing
--  6 Line is up
--  7 Line is busy
--
local function ChannelStatus(self, channel)
    channel = channel or ''

    return Execute(self, string.format('CHANNEL STATUS %s', tostring(channel)))
end

-- Send the given file, allowing playback to be controled by the given digits (if any)
-- Returns:
--  -1 on error or hangup
--  0 if playback completes without a digit being pressed
--  the ASCII numerical value of the digit of one was pressed
--
local function ControlStreamFile(self, filename, digits, skipms, ffchar, rewchar, pausechar)
    if not filename then
	return false
    end

    digits = digits or '""'
    skipms = skipms or ''
    ffchar = ffchar or ''
    rewchar = rewchar or ''
    pausechar = pausechar or ''

    return Execute(
	self, 
	string.format(
	    'CONTROL STREAM FILE %s %s %s %s %s %s', 
	    tostring(filename), 
	    tostring(digits), 
	    tostring(skipms), 
	    tostring(ffchar), 
	    tostring(rewchar), 
	    tostring(pausechar)
	)
    )
end

-- Removes database entry <family>/<key>
local function DatabaseDel(self, family, key)
    family = family or ''
    key = key or ''

    return Execute(self, string.format('DATABASE DEL %s %s', tostring(family), tostring(key)))
end

-- Deletes a family or specific keytree within a family in the Asterisk database
local function DatabaseDeltree(self, family, key)
    family = family or ''
    key = key or ''

    return Execute(self, string.format('DATABASE DELTREE %s %s', tostring(family), tostring(key)))
end

-- Returns: The value of the variable, or nil if variable does not exist
local function DatabaseGet(self, family, key)
    local value = nil

    family = family or ''
    key = key or ''

    if Execute(self, string.format('DATABASE GET %s %s', tostring(family), tostring(key))) then
	local temp = self.last_result

	value = string.gsub(temp, '\((.*)\)', '%1')
    end

    return value
end

-- Set/modifes database entry <family>/<key> to <value>
local function DatabasePut(self, family, key, value)
    family = family or ''
    key = key or ''
    value = value or ''

    return Execute(
	self, 
	string.format(
	    'DATABASE PUT %s %s %s', 
	    tostring(family), 
	    tostring(key), 
	    tostring(value)
	)
    ) 
end

-- Executes the given application passing the given options.
local function Exec(self, app, options)
    if not app then
	return false
    end

    options = options or ''

    return Execute(self, string.format('EXEC %s "%s"', tostring(app), tostring(options)))
end

-- Streams filename and returns when maxdigits have been received or
-- when timeout has been reached.  Timeout is specified in ms
local function GetData(self, filename, timeout, maxdigits)
    if not filename then
	return false
    end

    timeout = timeout or 0
    maxdigits = maxdigits or 1

    return Execute(
	self, 
	string.format(
	    'GET DATA %s %d %d', 
	    tostring(filename), 
	    tonumber(timeout), 
	    tonumber(maxdigits)
	)
    )
end

-- Similar to get_variable, but additionally understands
-- complex variable names and builtin variables.  If channel is not set, uses the
-- current channel.
local function GetFullVariable(self, variable, channel)
    local value = nil
    channel = channel or ''

    if Execute(self, string.format('GET FULL VARIABLE %s %s', tostring(variable), tostring(channel))) then
	local temp = self.last_result

	value = string.gsub(temp, '\((.*)\)', '%1')
    end

    return value
end

-- Behaves similar to STREAM FILE but used with a timeout option.
--
-- Streams filename and returns when digits is pressed or when timeout has been
-- reached.  Timeout is specified in ms.  If timeout is not specified, the command
-- will only terminate on the digits set.
local function GetOption(self, filename, digits, timeout)
    if not filename then
	return false
    end

    digits = digits or '""'
    timeout = timeout or 0

    return Execute(
	self, 
	string.format(
	    'GET OPTION %s %s %d', 
	    tostring(filename), 
	    tostring(digits), 
	    tonumber(timeout)
	)
    )
end

-- Gets the channel variable <variablename>
local function GetVariable(self, variable)
    local value = nil

    if Execute(self, string.format('GET VARIABLE %s', tostring(variable))) then
	local temp = self.last_result

	value = string.gsub(temp, '\((.*)\)', '%1')
    end

    return value
end

-- Hangs up the passed channel, or the current channel if channel is not passed.
local function Hangup(self, channel)
    channel = channel or ''

    return Execute(self, string.format('HANGUP %s', tostring(channel)))
end

-- Does absolutely nothing except pop up a log message.  
-- Useful for outputting debugging information to the Asterisk console.
local function Noop(self)
    return Execute(self, 'NOOP')
end

-- Receives a character of text on a channel. Specify timeout to be the maximum
-- time to wait for input in milliseconds, or 0 for infinite. Most channels do not
-- support the reception of text. 
local function ReceiveChar(self, timeout)
    timeout = timeout or 0

    return Execute(self, string.format('RECEIVE CHAR %d', tonumber(timeout)))
end

-- Receives a string of text on a channel. Specify timeout to be the maximum time
-- to wait for input in milliseconds, or 0 for infinite. Most channels do not
-- support the reception of text. 
local function ReceiveText(self, timeout)
    timeout = timeout or 0

    return Execute(self, string.format('RECEIVE TEXT %d', tonumber(timeout)))
end

-- Record to a file until digits are received as dtmf.
local function RecordFile(self, filename, format, digits, timeout, offset, beep, silence)
    if not filename then
	return false
    end

    local extras = {}

    format = format or ''
    digits = digits or '""'
    timeout = timeout or ''

    if offset then
	table.insert(extras, offset)
    end

    if beep then
	table.insert(extras, beep)
    end

    if silence then
	table.insert(extras, 's=' .. silence)
    end

    local extra = table.concat(extras, ' ')

    return Execute(
	self, 
	string.format(
	    'RECORD FILE %s %s %s %s %s', 
	    tostring(filename), 
	    tostring(format), 
	    tostring(digits), 
	    tostring(timeout), 
	    tostring(extra)
	)
    )
end

-- Say a given character string, returning early if any of the given DTMF digits
-- are received on the channel. 
local function SayAlpha(self, string, digits)
    if not string then
	return false
    end

    string = string or ''
    digits = digits or '""'

    return Execute(self, string.format('SAY ALPHA %s %s', tostring(string), tostring(digits)))
end

-- Say a given date, returning early if any of the optional DTMF digits are
-- received on the channel. time is in unixtime
local function SayDate(self, time, digits)
    if not time then
	return false
    end

    digits = digits or '""'

    return Execute(self, string.format('SAY DATE %d %s', tonumber(time), tostring(digits)))
end

-- Say a given datetime, returning early if any of the optional DTMF digits are
-- received on the channel. time is in unixtime
local function SayDateTime(self, time, digits, format, timezone)
    if not time then
	return false
    end

    digits = digits or '""'
    format = format or '""'
    timezone = timezone or '""'

    return Execute(
	self, 
	string.format(
	    'SAY DATETIME %d %s %s %s', 
	    tonumber(time), 
	    tostring(digits), 
	    tostring(format), 
	    tostring(timezone)
	)
    )
end

-- Say a given time, returning early if any of the optional DTMF digits are
-- received on the channel. time is in unixtime
local function SayTime(self, time, digits)
    if not time then
	return false
    end

    digits = digits or '""'

    return Execute(self, string.format('SAY TIME %s %s', tonumber(time), tostring(digits)))
end

-- Says the given digit string number, returning early if any of the digits are received.
local function SayDigits(self, number, digits)
    if not number then
	return false
    end

    digits = digits or '""'

    return Execute(self, string.format('SAY DIGITS %s %s', tostring(number), tostring(digits)))
end

-- Says the given number, returning early if any of the digits are received.
local function SayNumber(self, number, digits)
    if not number then
	return false
    end

    digits = digits or '""'

    return Execute(self, string.format('SAY NUMBER %s %s', tostring(number), tostring(digits)))
end

-- Say a given character string with phonetics, returning early if any of the
-- given DTMF digits are received on the channel.
local function SayPhonetic(self, string, digits)
    if not string then
	return false
    end

    digits = digits or '""'

    return Execute(self, string.format('SAY PHONETIC %s %s', tostring(string), tostring(digits)))
end

-- Sends the given image on a channel.  Most channels do not support the transmission of images.
local function SendImage(self, image)
    if not image then
	return false
    end

    return Execute(self, string.format('SEND TEXT %s', tostring(image)))
end

-- Sends the given text on a channel.  Most channels do not support the transmission of text.
local function SendText(self, text)
    if not text then
	return false
    end

    return Execute(self, string.format('SEND TEXT %s', tostring(text)))
end

-- Cause the channel to automatically hangup at <time> seconds in the future.
-- Setting to 0 will cause the autohangup feature to be disabled on this channel.
local function SetAutoHangup(self, time)
    if not time then
	time = 0
    end

    return Execute(self, string.format('SET AUTOHANGUP %d', tonumber(time)))
end

-- Changes the callerid of the current channel to <number>
local function SetCallerID(self, id)
    if not id then
	return false
    end

    return Execute(self, string.format('SET CALLERID %s', tostring(id)))
end

-- Changes the context for continuation upon exiting the agi application
local function SetContext(self, context)
    if not context then
	return false
    end

    return Execute(self, string.format('SET CONTEXT %s', tostring(context)))
end

-- Changes the extension for continuation upon exiting the agi application
local function SetExtension(self, extension)
    if not extension then
	return false
    end

    return Execute(self, string.format('SET EXTENSION %s', tostring(extension)))
end

-- Enables/Disables the music on hold generator.
local function SetMusic(self, mode, class)
    mode = mode or ''
    class = class or ''

    return Execute(self, string.format('SET MUSIC %s %s', tostring(mode), tostring(class)))
end

-- Changes the priority for continuation upon exiting the agi application
local function SetPriority(self, priority)
    if not priority then
	return false
    end

    return Execute(self, string.format('SET PRIORITY %s', tostring(channel)))
end

-- Sets the channel variable <variablename> to <value>
local function SetVariable(self, variable, value)
    variable = variable or ''
    value = value or ''

    return Execute(self, string.format('SET VARIABLE %s %s', tostring(variable), tostring(value)))
end

-- This command instructs Asterisk to play the given sound file and listen for the given dtmf digits
local function StreamFile(self, filename, digits)
    if not filename then
	return false
    end

    digits = digits or '""'

    return Execute(self, string.format('STREAM FILE %s %s', tostring(filename), tostring(digits)))
end

-- Enable/Disable TDD transmission/reception on a channel.
local function TDDMode(self, mode)
    if not mode then
	return false
    end

    return Execute(self, string.format('TDD MODE %s', tostring(message)))
end

-- Logs message with verbose level level
local function Verbose(self, message, level)
    message = message or ''
    level = level or ''

    return Execute(self, string.format('VERBOSE "%s" %s', tostring(message), tostring(level)))
end

-- Waits up to 'timeout' milliseconds for channel to receive a DTMF digit.
local function WaitForDigit(self, timeout)
    if not timeout then
	return false
    end

    return Execute(self, string.format('WAIT FOR DIGIT %d', tonumber(timeout)))
end

function New()
    local agi = {
	callback = nil,
	status = nil,
	last_response = nil,
	last_result = nil,
	hungup = false,
	debug = 0,
	env = nil,
    }

    agi.ReadParse = ReadParse
    agi.SetCallback = SetCallback
    agi.Callback = Callback
    agi.Answer = Answer
    agi.ChannelStatus = ChannelStatus
    agi.ControlStreamFile = ControlStreamFile
    agi.DatabaseDel = DatabaseDel
    agi.DatabaseDeltree = DatabaseDeltree
    agi.DatabaseGet = DatabaseGet
    agi.DatabasePut = DatabasePut
    agi.Exec = Exec
    agi.GetData = GetData
    agi.GetFullVariable = GetFullVariable
    agi.GetOption = GetOption
    agi.GetVariable = GetVariable
    agi.Hangup = Hangup
    agi.Noop = Noop
    agi.ReceiveChar = ReceiveChar
    agi.ReceiveText = ReceiveText
    agi.RecordFile = RecordFile
    agi.SayAlpha = SayAlpha
    agi.SayDate = SayDate
    agi.SayDateTime = SayDateTime
    agi.SayTime = SayTime
    agi.SayDigits = SayDigits
    agi.SayNumber = SayNumber
    agi.SayPhonetic = SayPhonetic
    agi.SendImage = SendImage
    agi.SendText = SendText
    agi.SetAutoHangup = SetAutoHangup
    agi.SetCallerID = SetCallerID
    agi.SetContext = SetContext
    agi.SetExtension = SetExtension
    agi.SetMusic = SetMusic
    agi.SetPriority = SetPriority
    agi.SetVariable = SetVariable
    agi.StreamFile = StreamFile
    agi.TDDMode = TDDMode
    agi.Verbose = Verbose
    agi.WaitForDigit = WaitForDigit

    return agi
end

--
-- AGI.lua
--
-- A module for interacting with Asterisk via AGI.
--
--
--
-- Synopsis
--
-- require('AGI')
--
-- agi = AGI.New()
-- env = agi:ReadParse()
-- 
-- agi:Verbose('Some Message')
-- agi:SayAlpha('test123')
-- agi:SetExtension('123')
--
