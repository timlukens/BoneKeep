/client/var/adminhelptimerid = 0	//a timer id for returning the ahelp verb
/client/var/datum/admin_help/current_ticket	//the current ticket the (usually) not-admin client is dealing with

//
//TICKET MANAGER
//

GLOBAL_DATUM_INIT(ahelp_tickets, /datum/admin_help_tickets, new)

/datum/admin_help_tickets
	var/list/active_tickets = list()
	var/list/closed_tickets = list()
	var/list/resolved_tickets = list()

	var/obj/effect/statclick/ticket_list/astatclick = new(null, null, AHELP_ACTIVE)
	var/obj/effect/statclick/ticket_list/cstatclick = new(null, null, AHELP_CLOSED)
	var/obj/effect/statclick/ticket_list/rstatclick = new(null, null, AHELP_RESOLVED)

/datum/admin_help_tickets/Destroy()
	QDEL_LIST(active_tickets)
	QDEL_LIST(closed_tickets)
	QDEL_LIST(resolved_tickets)
	QDEL_NULL(astatclick)
	QDEL_NULL(cstatclick)
	QDEL_NULL(rstatclick)
	return ..()

/datum/admin_help_tickets/proc/TicketByID(id)
	var/list/lists = list(active_tickets, closed_tickets, resolved_tickets)
	for(var/I in lists)
		for(var/J in I)
			var/datum/admin_help/AH = J
			if(AH.id == id)
				return J

/datum/admin_help_tickets/proc/TicketsByCKey(ckey)
	. = list()
	var/list/lists = list(active_tickets, closed_tickets, resolved_tickets)
	for(var/I in lists)
		for(var/J in I)
			var/datum/admin_help/AH = J
			if(AH.initiator_ckey == ckey)
				. += AH

//private
/datum/admin_help_tickets/proc/ListInsert(datum/admin_help/new_ticket)
	var/list/ticket_list
	switch(new_ticket.state)
		if(AHELP_ACTIVE)
			ticket_list = active_tickets
		if(AHELP_CLOSED)
			ticket_list = closed_tickets
		if(AHELP_RESOLVED)
			ticket_list = resolved_tickets
		else
			CRASH("Invalid ticket state: [new_ticket.state]")
	var/num_closed = ticket_list.len
	if(num_closed)
		for(var/I in 1 to num_closed)
			var/datum/admin_help/AH = ticket_list[I]
			if(AH.id > new_ticket.id)
				ticket_list.Insert(I, new_ticket)
				return
	ticket_list += new_ticket

//opens the ticket listings for one of the 3 states
/datum/admin_help_tickets/proc/BrowseTickets(state)
	var/list/l2b
	var/title
	switch(state)
		if(AHELP_ACTIVE)
			l2b = active_tickets
			title = "Active Tickets"
		if(AHELP_CLOSED)
			l2b = closed_tickets
			title = "Closed Tickets"
		if(AHELP_RESOLVED)
			l2b = resolved_tickets
			title = "Resolved Tickets"
	if(!l2b)
		return
	var/list/dat = list("<html><head><title>[title]</title></head>")
	dat += "<A href='?_src_=holder;[HrefToken()];ahelp_tickets=[state]'>Refresh</A><br><br>"
	for(var/I in l2b)
		var/datum/admin_help/AH = I
		dat += "<span class='adminnotice'><span class='adminhelp'>Ticket #[AH.id]</span>: <A href='?_src_=holder;[HrefToken()];ahelp=[REF(AH)];ahelp_action=ticket'>[AH.initiator_key_name]: [AH.name]</A></span><br>"

	usr << browse(dat.Join(), "window=ahelp_list[state];size=600x480")

//Tickets statpanel
/datum/admin_help_tickets/proc/stat_entry()
	var/num_disconnected = 0
	stat("Active Tickets:", astatclick.update("[active_tickets.len]"))
	for(var/I in active_tickets)
		var/datum/admin_help/AH = I
		if(AH.initiator)
			stat("#[AH.id]. [AH.initiator_key_name]:", AH.statclick.update())
		else
			++num_disconnected
	if(num_disconnected)
		stat("Disconnected:", astatclick.update("[num_disconnected]"))
	stat("Closed Tickets:", cstatclick.update("[closed_tickets.len]"))
	stat("Resolved Tickets:", rstatclick.update("[resolved_tickets.len]"))

//Reassociate still open ticket if one exists
/datum/admin_help_tickets/proc/ClientLogin(client/C)
	C.current_ticket = CKey2ActiveTicket(C.ckey)
	if(C.current_ticket)
		C.current_ticket.initiator = C
		C.current_ticket.AddInteraction("Client reconnected.")
		SSplexora.aticket_connection(C.current_ticket, FALSE)

//Dissasociate ticket
/datum/admin_help_tickets/proc/ClientLogout(client/C)
	if(C.current_ticket)
		SSplexora.aticket_connection(C.current_ticket)
		C.current_ticket.AddInteraction("Client disconnected.")
		C.current_ticket.initiator = null
		C.current_ticket = null

//Get a ticket given a ckey
/datum/admin_help_tickets/proc/CKey2ActiveTicket(ckey)
	for(var/I in active_tickets)
		var/datum/admin_help/AH = I
		if(AH.initiator_ckey == ckey)
			return AH

//
//TICKET LIST STATCLICK
//

/obj/effect/statclick/ticket_list
	var/current_state

/obj/effect/statclick/ticket_list/New(loc, name, state)
	current_state = state
	..()

/obj/effect/statclick/ticket_list/Click()
	GLOB.ahelp_tickets.BrowseTickets(current_state)

/**
 * # Adminhelp Ticket
 */
/datum/admin_help
	/// Unique ID of the ticket
	var/id
	/// The current name of the ticket
	var/name
	/// The current state of the ticket
	var/state = AHELP_ACTIVE
	/// The time at which the ticket was opened
	var/opened_at
	/// The time at which the ticket was closed
	var/closed_at
	/// Semi-misnomer, it's the person who ahelped/was bwoinked
	var/client/initiator
	/// The ckey of the initiator
	var/initiator_ckey
	/// The key name of the initiator
	var/initiator_key_name
	/// If any admins were online when the ticket was initialized
	var/heard_by_no_admins = FALSE
	/// The collection of interactions with this ticket. Use AddInteraction() or, preferably, admin_ticket_log()
	var/list/ticket_interactions
	/// List of player interactions
	var/list/player_interactions
	/// Statclick holder for the ticket
	var/obj/effect/statclick/ahelp/statclick
	/// Static counter used for generating each ticket ID
	var/static/ticket_counter = 0
	/// ckey of the admin that claimed this ticket.
	var/ticket_claimant_ckey

//call this on its own to create a ticket, don't manually assign current_ticket
//msg is the title of the ticket: usually the ahelp text
//is_bwoink is TRUE if this ticket was started by an admin PM
/datum/admin_help/New(msg, client/C, is_bwoink)
	//clean the input msg
	msg = sanitize(copytext(msg,1,MAX_MESSAGE_LEN))
	if(!msg || !C || !C.mob)
		qdel(src)
		return

	id = ++ticket_counter
	opened_at = world.time

	name = copytext_char(msg, 1, 100)

	initiator = C
	initiator_ckey = initiator.ckey
	initiator_key_name = key_name(initiator, FALSE, TRUE)
	if(initiator.current_ticket)	//This is a bug
		stack_trace("Multiple ahelp current_tickets")
		initiator.current_ticket.AddInteraction("Ticket erroneously left open by code")
		initiator.current_ticket.Close()
	initiator.current_ticket = src

	TimeoutVerb()

	statclick = new(null, src)
	ticket_interactions = list()
	player_interactions = list()

	if(is_bwoink)
		AddInteraction("<font color='blue'>[key_name_admin(usr)] PM'd [LinkedReplyName()]</font>", player_message = "<font color='blue'>[LinkedReplyName(usr, FALSE)] PM'd [LinkedReplyName()]</font>")
		message_admins("<font color='blue'>[TicketHref("Ticket #[id]")] created</font>")
		SSplexora.aticket_new(src, msg, is_bwoink, TRUE, usr.ckey)
	else
		SSplexora.aticket_new(src, msg, is_bwoink, FALSE)
		MessageNoRecipient(msg)

		//send it to irc if nobody is on and tell us how many were on
		var/admin_number_present = send2irc_adminless_only(initiator_ckey, "Ticket #[id]: [msg]")
		log_admin_private("Ticket #[id]: [key_name(initiator)]: [name] - heard by [admin_number_present] non-AFK admins who have +BAN.")
		if(admin_number_present <= 0)
			to_chat(C, "<span class='notice'>No active admins are online, my adminhelp was sent to the admins via Plexora.</span>")
			heard_by_no_admins = TRUE

	GLOB.ahelp_tickets.active_tickets += src

/datum/admin_help/Destroy()
	RemoveActive()
	GLOB.ahelp_tickets.closed_tickets -= src
	GLOB.ahelp_tickets.resolved_tickets -= src
	return ..()

/datum/admin_help/proc/AddInteraction(formatted_message, player_message)
	if(heard_by_no_admins && usr && usr.ckey != initiator_ckey)
		heard_by_no_admins = FALSE
		send2irc(initiator_ckey, "Ticket #[id]: Answered by [key_name(usr)]")

	ticket_interactions += "[time_stamp()]: [formatted_message]"
	if(!isnull(player_message))
		player_interactions += "[time_stamp()]: [player_message]"

//Removes the ahelp verb and returns it after 2 minutes
/datum/admin_help/proc/TimeoutVerb()
	initiator.verbs -= /client/verb/adminhelp
	initiator.adminhelptimerid = addtimer(CALLBACK(initiator, TYPE_PROC_REF(/client, giveadminhelpverb)), 1200, TIMER_STOPPABLE) //2 minute cooldown of admin helps

//private
/datum/admin_help/proc/FullMonty(ref_src)
	if(!ref_src)
		ref_src = "[REF(src)]"
	. = ADMIN_FULLMONTY_NONAME(initiator.mob)
	if(state == AHELP_ACTIVE)
		. += ClosureLinks(ref_src)
	. += claim_link(ref_src)

/datum/admin_help/proc/limited_monty(ref_src)
	if(!ref_src)
		ref_src = "[REF(src)]"
	. = ADMIN_MONTY_LIMITED(initiator.mob)
	. += claim_link()

//private
/datum/admin_help/proc/ClosureLinks(ref_src)
	if(!ref_src)
		ref_src = "[REF(src)]"
	. = " (<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=reject'>REJT</A>)"
	. += " (<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=icissue'>IC</A>)"
	. += " (<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=mentorissue'>MENTOR</A>)"
	. += " (<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=close'>CLOSE</A>)"
	. += " (<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=resolve'>RSLVE</A>)"

/datum/admin_help/proc/claim_link(ref_src)
	if(!ref_src)
		ref_src = "[REF(src)]"
	. = " (<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=claimticket'>CLAIM</A>)"

//private
/datum/admin_help/proc/LinkedReplyName(ref_src)
	if(!ref_src)
		ref_src = "[REF(src)]"
	return "<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=reply'>[initiator_key_name]</A>"

//private
/datum/admin_help/proc/TicketHref(msg, ref_src, action = "ticket")
	if(!ref_src)
		ref_src = "[REF(src)]"
	return "<A HREF='?_src_=holder;[HrefToken(TRUE)];ahelp=[ref_src];ahelp_action=[action];color:red'>[msg]</A>"

//message from the initiator without a target, all admins will see this
//won't bug irc
/datum/admin_help/proc/MessageNoRecipient(msg)
	var/ref_src = "[REF(src)]"
	//Message to be sent to all admins
	var/admin_msg = "<span class='adminnotice'><span class='adminhelp'>[TicketHref("Ticket #[id]", ref_src)]</span><b>: [LinkedReplyName(ref_src)] [limited_monty(ref_src)] </b> <span class='linkify'>[keywords_lookup(msg)]</span></span>"

	AddInteraction("<font color='red'>[LinkedReplyName(ref_src)]: [msg]</font>", player_message = "<font color='red'>[LinkedReplyName(ref_src)]: [msg]</font>")
	log_admin_private("Ticket #[id]: [key_name(initiator)]: [msg]")

	//send this msg to all admins
	for(var/client/X in GLOB.admins)
		if(X.ckey == "dwasint") ///I FUCKING HATE THIS SOUND
			continue
		SEND_SOUND(X, sound('sound/misc/adminhelp.ogg'))
		window_flash(X, ignorepref = TRUE)
		to_chat(X, admin_msg)

	//show it to the person adminhelping too
	to_chat(initiator, "<span class='adminnotice'>PM to-<b>Admins</b>: <span class='linkify'>[msg]</span></span>")

//Reopen a closed ticket
/datum/admin_help/proc/Reopen()
	if(state == AHELP_ACTIVE)
		to_chat(usr, "<span class='warning'>This ticket is already open.</span>")
		return

	if(GLOB.ahelp_tickets.CKey2ActiveTicket(initiator_ckey))
		to_chat(usr, "<span class='warning'>This user already has an active ticket, cannot reopen this one.</span>")
		return

	statclick = new(null, src)
	GLOB.ahelp_tickets.active_tickets += src
	GLOB.ahelp_tickets.closed_tickets -= src
	GLOB.ahelp_tickets.resolved_tickets -= src
	switch(state)
		if(AHELP_CLOSED)
			SSblackbox.record_feedback("tally", "ahelp_stats", -1, "closed")
		if(AHELP_RESOLVED)
			SSblackbox.record_feedback("tally", "ahelp_stats", -1, "resolved")
	state = AHELP_ACTIVE
	closed_at = null
	if(initiator)
		initiator.current_ticket = src

	AddInteraction("<font color='purple'>Reopened by [key_name_admin(usr)]</font>", player_message = "Ticket reopened!")
	var/msg = "<span class='adminhelp'>[TicketHref("Ticket #[id]")] reopened by [key_name_admin(usr)].</span>"
	message_admins(msg)
	log_admin_private(msg)
	SSblackbox.record_feedback("tally", "ahelp_stats", 1, "reopened")
	SSplexora.aticket_reopened(src, usr.ckey)
	TicketPanel()	//can only be done from here, so refresh it

//private
/datum/admin_help/proc/RemoveActive()
	if(state != AHELP_ACTIVE)
		return
	closed_at = world.time
	QDEL_NULL(statclick)
	GLOB.ahelp_tickets.active_tickets -= src
	if(initiator && initiator.current_ticket == src)
		initiator.current_ticket = null

//Mark open ticket as closed/meme
/datum/admin_help/proc/Close(key_name = key_name_admin(usr), silent = FALSE)
	if(state != AHELP_ACTIVE)
		return
	RemoveActive()
	state = AHELP_CLOSED
	GLOB.ahelp_tickets.ListInsert(src)
	AddInteraction("<font color='red'>Closed by [key_name].</font>", player_message = "<font color='red'>Ticket closed!</font>")
	if(!silent)
		SSblackbox.record_feedback("tally", "ahelp_stats", 1, "closed")
		var/msg = "[TicketHref("Ticket #[id]")] closed by [key_name]."
		message_admins(msg)
		log_admin_private(msg)

/// claims or unclaims the ticket for the admin, gives an option if it was already claimed and returns false if they decided not to claim it.
/datum/admin_help/proc/claim_ticket(key_name = key_name_admin(usr), silent = FALSE)
	if(ticket_claimant_ckey == usr.client.ckey)
		unclaim_ticket(key_name)
		return TRUE

	ticket_claimant_ckey = usr.client.ckey
	SSblackbox.record_feedback("tally", "ahelp_stats", 1, "ticket_claimed")
	AddInteraction("[ticket_claimant_ckey] has claimed Ticket #[id]")
	message_admins("[usr.key] claimed [TicketHref("Ticket #[id]")]!")

/// unclaims the ticket.
/datum/admin_help/proc/unclaim_ticket(key_name = key_name_admin(usr), silent = FALSE)
	ticket_claimant_ckey = null
	SSblackbox.record_feedback("tally", "ahelp_stats", 1, "ticket_unclaimed")
	AddInteraction("[ticket_claimant_ckey] has UNclaimed Ticket #[id]")
	message_admins("[usr.key] UNclaimed [TicketHref("Ticket #[id]")]!")

/// checks if the admin has the ticket claimed, if not - make sure they want to perform the action.
/datum/admin_help/proc/claim_assert(key_name = key_name_admin(usr), silent = FALSE)
	if(!ticket_claimant_ckey) // if no one has claimed the ticket already then claim it.
		claim_ticket()
		return TRUE
	if(ticket_claimant_ckey != usr.client.ckey)
		if(alert("Already claimed by[ticket_claimant_ckey]! do it anyways?",,"Yes","No") == "No")
			return FALSE
	return TRUE

//Resolve ticket with mentorhelp Issue message
/datum/admin_help/proc/mentorissue(key_name = key_name_admin(usr))
	if(state != AHELP_ACTIVE)
		return

	var/msg = "<font color='red' size='4'><b>- AdminHelp marked as ingame mechanics issue! -</b></font><br>"
	msg += "<font color='red'>My issue has been determined by an administrator to be related to ingame mechanics, For further resolution please use <a href='byond://winset?command=mentorhelp'>MENTOR HELP</span></a>, LOOC, the <a href='byond://winset?command=wiki'>WIKI</span></a>, or osseus questions on Discord if nobody is responding to a meditation..</font>"

	if(initiator)
		to_chat(initiator, msg)

	SSblackbox.record_feedback("tally", "ahelp_stats", 1, "")
	msg = "[TicketHref("Ticket #[id]")] marked as mechanics issue by [key_name]"
	message_admins(msg)
	log_admin_private(msg)
	AddInteraction("Marked as mechanics issue by [key_name]", player_message = "<font color='green'>Marked as mechanics issue!</font>")
	Resolve(silent = TRUE)

//Mark open ticket as resolved/legitimate, returns ahelp verb
/datum/admin_help/proc/Resolve(key_name = key_name_admin(usr), silent = FALSE)
	if(state != AHELP_ACTIVE)
		return
	RemoveActive()
	state = AHELP_RESOLVED
	GLOB.ahelp_tickets.ListInsert(src)

	addtimer(CALLBACK(initiator, TYPE_PROC_REF(/client, giveadminhelpverb)), 50)

	AddInteraction("<font color='green'>Resolved by [key_name].</font>", player_message = "<font color='green'>Ticket resolved!</font>")
	to_chat(initiator, "<span class='adminhelp'>My ticket has been resolved by an admin. The Adminhelp verb will be returned to you shortly.</span>")
	if(!silent)
		SSblackbox.record_feedback("tally", "ahelp_stats", 1, "resolved")
		var/msg = "[TicketHref("Ticket #[id]")] resolved by [key_name]"
		message_admins(msg)
		log_admin_private(msg)

//Close and return ahelp verb, use if ticket is incoherent
/datum/admin_help/proc/Reject(key_name = key_name_admin(usr))
	if(state != AHELP_ACTIVE)
		return
	if(initiator)
		initiator.giveadminhelpverb()

		SEND_SOUND(initiator, sound('sound/blank.ogg'))

		to_chat(initiator, "<font color='red' size='4'><b>- AdminHelp Rejected! -</b></font>")
		to_chat(initiator, "<font color='red'><b>My admin help was rejected.</b> The adminhelp verb has been returned to you so that you may try again.</font>")
		to_chat(initiator, "Please try to be calm, clear, and descriptive in admin helps, do not assume the admin has seen any related events, and clearly state the names of anybody you are reporting.")

	SSblackbox.record_feedback("tally", "ahelp_stats", 1, "rejected")
	var/msg = "[TicketHref("Ticket #[id]")] rejected by [key_name]"
	message_admins(msg)
	log_admin_private(msg)
	AddInteraction("Rejected by [key_name].", player_message = "Ticket rejected!")
	Close(silent = TRUE)

//Resolve ticket with IC Issue message
/datum/admin_help/proc/ICIssue(key_name = key_name_admin(usr))
	if(state != AHELP_ACTIVE)
		return
	var/msg = "<font color='red' size='4'><b>- AdminHelp marked as IC issue! -</b></font><br>"
	msg += "<font color='red'>My issue has been determined by an administrator to be an in character issue and does NOT require administrator intervention at this time. For further resolution you should pursue options that are in character.</font>"

	if(initiator)
		to_chat(initiator, msg)

	SSblackbox.record_feedback("tally", "ahelp_stats", 1, "IC")
	msg = "[TicketHref("Ticket #[id]")] marked as IC by [key_name]"
	message_admins(msg)
	log_admin_private(msg)
	AddInteraction("Marked as IC issue by [key_name]", player_message = "Marked as IC issue!")
	Resolve(silent = TRUE)

//Show the ticket panel
/datum/admin_help/proc/TicketPanel()
	var/list/dat = list("<html><head><title>Ticket #[id]</title></head>")
	var/ref_src = "[REF(src)]"
	dat += "<h4>Admin Help Ticket #[id]: [LinkedReplyName(ref_src)]</h4>"
	if(usr.client?.holder)
		dat += "<h5>Ticket Claimed by [ticket_claimant_ckey ? ticket_claimant_ckey : "NONE"]</h5>"
	dat += "<b>State: "
	switch(state)
		if(AHELP_ACTIVE)
			dat += "<font color='red'>OPEN</font>"
		if(AHELP_RESOLVED)
			dat += "<font color='green'>RESOLVED</font>"
		if(AHELP_CLOSED)
			dat += "CLOSED"
		else
			dat += "UNKNOWN"
	dat += "</b>[FOURSPACES][TicketHref("Refresh", ref_src)][FOURSPACES][TicketHref("Re-Title", ref_src, "retitle")]"
	if(state != AHELP_ACTIVE)
		dat += "[FOURSPACES][TicketHref("Reopen", ref_src, "reopen")]"
	dat += "<br><br>Opened at: [gameTimestamp(wtime = opened_at)] (Approx [DisplayTimeText(world.time - opened_at)] ago)"
	if(closed_at)
		dat += "<br>Closed at: [gameTimestamp(wtime = closed_at)] (Approx [DisplayTimeText(world.time - closed_at)] ago)"
	dat += "<br><br>"
	if(initiator)
		dat += "<b>Actions:</b> [FullMonty(ref_src)]<br>"
	else
		dat += "<b>DISCONNECTED</b>[FOURSPACES][ClosureLinks(ref_src)]<br>"
	dat += "<br><b>Log:</b><br><br>"
	for(var/I in ticket_interactions)
		dat += "[I]<br>"

	usr << browse(dat.Join(), "window=ahelp[id];size=620x480")

/datum/admin_help/proc/Retitle()
	var/new_title = input(usr, "Enter a title for the ticket", "Rename Ticket", name) as text|null
	if(new_title)
		name = new_title
		//not saying the original name cause it could be a long ass message
		var/msg = "[TicketHref("Ticket #[id]")] titled [name] by [key_name_admin(usr)]"
		message_admins(msg)
		log_admin_private(msg)
	TicketPanel()	//we have to be here to do this

//Forwarded action from admin/Topic
/datum/admin_help/proc/Action(action)

	switch(action)
		if("claimticket")
			claim_ticket()
		if("ticket")
			TicketPanel()
		if("retitle")
			if(!claim_assert())
				return
			Retitle()
		if("reject")
			if(!claim_assert())
				return
			SSplexora.aticket_closed(src, usr.ckey, AHELP_CLOSETYPE_REJECT)
			Reject()
		if("reply")
			if(!claim_assert())
				return
			usr.client.cmd_ahelp_reply(initiator)
		if("icissue")
			if(!claim_assert())
				return
			SSplexora.aticket_closed(src, usr.ckey, AHELP_CLOSETYPE_RESOLVE, AHELP_CLOSEREASON_IC)
			ICIssue()
		if("mentorissue")
			if(!claim_assert())
				return
			SSplexora.aticket_closed(src, usr.ckey, AHELP_CLOSETYPE_RESOLVE, AHELP_CLOSEREASON_IC)
			mentorissue()
		if("close")
			if(!claim_assert())
				return
			SSplexora.aticket_closed(src, usr.ckey, AHELP_CLOSETYPE_CLOSE)
			Close()
		if("resolve")
			if(!claim_assert())
				return
			SSplexora.aticket_closed(src, usr.ckey, AHELP_CLOSETYPE_RESOLVE)
			Resolve()
		if("reopen")
			if(!claim_assert())
				return
			Reopen()

/datum/admin_help/proc/player_ticket_panel()
	var/list/dat = list("<html><head><meta http-equiv='Content-Type' content='text/html; charset=UTF-8'><title>Player Ticket</title></head>")
	dat += "<b>State: "
	switch(state)
		if(AHELP_ACTIVE)
			dat += "<font color='red'>OPEN</font></b>"
		if(AHELP_RESOLVED)
			dat += "<font color='green'>RESOLVED</font></b>"
		if(AHELP_CLOSED)
			dat += "CLOSED</b>"
		else
			dat += "UNKNOWN</b>"
	dat += "\n[FOURSPACES]<A href='byond://?_src_=holder;[HrefToken(forceGlobal = TRUE)];player_ticket_panel=1'>Refresh</A>"
	dat += "<br><br>Opened at: [gameTimestamp("hh:mm:ss", opened_at)] (Approx [DisplayTimeText(world.time - opened_at)] ago)"
	if(closed_at)
		dat += "<br>Closed at: [gameTimestamp("hh:mm:ss", closed_at)] (Approx [DisplayTimeText(world.time - closed_at)] ago)"
	dat += "<br><br>"
	dat += "<br><b>Log:</b><br><br>"
	for (var/interaction in player_interactions)
		dat += "[interaction]<br>"

	dat+= "<br><b>THIS IS AN EXPERIMENTAL FEATURE, REPORT ANY BUGS TO GITHUB!!</b><br>"

	var/datum/browser/player_panel = new(usr, "ahelp[id]", 0, 620, 480)
	player_panel.set_content(dat.Join())
	player_panel.open()

//
// TICKET STATCLICK
//

/obj/effect/statclick/ahelp
	var/datum/admin_help/ahelp_datum

/obj/effect/statclick/ahelp/Initialize(mapload, datum/admin_help/AH)
	ahelp_datum = AH
	. = ..()

/obj/effect/statclick/ahelp/update()
	return ..(ahelp_datum.name)

/obj/effect/statclick/ahelp/Click()
	ahelp_datum.TicketPanel()

/obj/effect/statclick/ahelp/Destroy()
	ahelp_datum = null
	return ..()

//
// CLIENT PROCS
//

/client/proc/giveadminhelpverb()
	src.verbs |= /client/verb/adminhelp
	deltimer(adminhelptimerid)
	adminhelptimerid = 0

// Used for methods where input via arg doesn't work
/client/proc/get_adminhelp()
	var/msg = input(src, "Please describe my problem concisely and an admin will help as soon as they're able.", "Adminhelp contents") as message|null
	adminhelp(msg)

/client/verb/adminhelp(msg as message)
	set category = "Admin"
	set name = "Adminhelp"

	if(GLOB.say_disabled)	//This is here to try to identify lag problems
		to_chat(usr, "<span class='danger'>Speech is currently admin-disabled.</span>")
		return

	//handle muting and automuting
	if(prefs.muted & MUTE_ADMINHELP)
		to_chat(src, "<span class='danger'>Error: Admin-PM: You cannot send adminhelps (Muted).</span>")
		return
	if(handle_spam_prevention(msg,MUTE_ADMINHELP))
		return

	msg = trim(msg)

	if(!msg)
		return

	SSblackbox.record_feedback("tally", "admin_verb", 1, "Adminhelp") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	if(current_ticket)
		if(alert(usr, "You already have a ticket open. Is this for the same issue?",,"Yes","No") != "No")
			if(current_ticket)
				current_ticket.MessageNoRecipient(msg)
				current_ticket.TimeoutVerb()
				return
			else
				to_chat(usr, "<span class='warning'>Ticket not found, creating new one...</span>")
		else
			current_ticket.AddInteraction("[key_name_admin(usr)] opened a new ticket.", player_message = "opened a new ticket.")
			current_ticket.Close()

	new /datum/admin_help(msg, src, FALSE)


/client/proc/self_notes()
	set name = "View Admin Remarks"
	set category = "Admin"
	set desc = "View the notes that admins have written about you"

	browse_messages(null, usr.ckey, null, TRUE)

/client/verb/view_latest_ticket()
	set category = "Admin"
	set name = "View Latest Ticket"


	if(!current_ticket)
		// Check if the client had previous tickets, and show the latest one
		var/list/prev_tickets = list()
		var/datum/admin_help/last_ticket
		// Check all resolved tickets for this player
		for(var/datum/admin_help/resolved_ticket in GLOB.ahelp_tickets.resolved_tickets)
			if(resolved_ticket.initiator_ckey == ckey) // Initiator is a misnomer, it's always the non-admin player even if an admin bwoinks first
				prev_tickets += resolved_ticket
		// Check all closed tickets for this player
		for(var/datum/admin_help/closed_ticket in GLOB.ahelp_tickets.closed_tickets)
			if(closed_ticket.initiator_ckey == ckey)
				prev_tickets += closed_ticket
		// Take the most recent entry of prev_tickets and open the panel on it
		if(LAZYLEN(prev_tickets))
			last_ticket = pop(prev_tickets)
			last_ticket.player_ticket_panel()
			return

		// client had no tickets this round
		to_chat(src, span_warning("You have not had an ahelp ticket this round."))
		return

	current_ticket.player_ticket_panel()

//
// LOGGING
//


/// Use this proc when an admin takes action that may be related to an open ticket on what
/// what can be a client, ckey, or mob
/// player_message: If the message should be shown in the player ticket panel, fill this out
/proc/admin_ticket_log(what, message, player_message)
	var/client/mob_client
	var/mob/Mob = what
	if(istype(Mob))
		mob_client = Mob.client
	else
		mob_client = what
	if(istype(mob_client) && mob_client.current_ticket)
		if (isnull(player_message))
			mob_client.current_ticket.AddInteraction(message)
		else
			mob_client.current_ticket.AddInteraction(message, player_message)
		return mob_client.current_ticket
	if(istext(what)) //ckey
		var/datum/admin_help/active_admin_help = GLOB.ahelp_tickets.CKey2ActiveTicket(what)
		if(active_admin_help)
			if(isnull(player_message))
				active_admin_help.AddInteraction(message)
			else
				active_admin_help.AddInteraction(message, player_message)
			return active_admin_help

//
// HELPER PROCS
//

/proc/get_admin_counts(requiredflags = R_BAN)
	. = list("total" = list(), "noflags" = list(), "afk" = list(), "stealth" = list(), "present" = list())
	for(var/client/X in GLOB.admins)
		.["total"] += X
		if(requiredflags != 0 && !check_rights_for(X, requiredflags))
			.["noflags"] += X
		else if(X.is_afk())
			.["afk"] += X
		else if(X.holder.fakekey)
			.["stealth"] += X
		else
			.["present"] += X

/proc/send2irc_adminless_only(source, msg, requiredflags = R_BAN)
	var/list/adm = get_admin_counts(requiredflags)
	var/list/activemins = adm["present"]
	. = activemins.len
	if(. <= 0)
		var/final = ""
		var/list/afkmins = adm["afk"]
		var/list/stealthmins = adm["stealth"]
		var/list/powerlessmins = adm["noflags"]
		var/list/allmins = adm["total"]
		if(!afkmins.len && !stealthmins.len && !powerlessmins.len)
			final = "[msg] - No admins online"
		else
			final = "[msg] - All admins stealthed\[[english_list(stealthmins)]\], AFK\[[english_list(afkmins)]\], or lacks +BAN\[[english_list(powerlessmins)]\]! Total: [allmins.len] "
		send2irc(source,final)
		send2otherserver(source,final)


/proc/send2irc(msg,msg2)
	msg = replacetext(replacetext(msg, "\proper", ""), "\improper", "")
	msg2 = replacetext(replacetext(msg2, "\proper", ""), "\improper", "")
	world.TgsTargetedChatBroadcast("[msg] | [msg2]", TRUE)

/proc/send2otherserver(source,msg,type = "Ahelp")
	var/comms_key = CONFIG_GET(string/comms_key)
	if(!comms_key)
		return
	var/list/message = list()
	message["message_sender"] = source
	message["message"] = msg
	message["source"] = "([CONFIG_GET(string/cross_comms_name)])"
	message["key"] = comms_key
	message += type

	var/list/servers = CONFIG_GET(keyed_list/cross_server)
	for(var/I in servers)
		world.Export("[servers[I]]?[list2params(message)]")


/proc/ircadminwho()
	var/list/message = list("Admins: ")
	var/list/admin_keys = list()
	for(var/adm in GLOB.admins)
		var/client/C = adm
		admin_keys += "[C][C.holder.fakekey ? "(Stealth)" : ""][C.is_afk() ? "(AFK)" : ""]"

	for(var/admin in admin_keys)
		if(LAZYLEN(message) > 1)
			message += ", [admin]"
		else
			message += "[admin]"

	return jointext(message, "")

/proc/keywords_lookup(msg,irc)

	//This is a list of words which are ignored by the parser when comparing message contents for names. MUST BE IN LOWER CASE!
	var/list/adminhelp_ignored_words = list("unknown","the","a","an","of","monkey","alien","as", "i")

	//explode the input msg into a list
	var/list/msglist = splittext(msg, " ")

	//generate keywords lookup
	var/list/surnames = list()
	var/list/forenames = list()
	var/list/ckeys = list()
	var/founds = ""
	for(var/mob/M in GLOB.mob_list)
		var/list/indexing = list(M.real_name, M.name)
		if(M.mind)
			indexing += M.mind.name

		for(var/string in indexing)
			var/list/L = splittext(string, " ")
			var/surname_found = 0
			//surnames
			for(var/i=L.len, i>=1, i--)
				var/word = ckey(L[i])
				if(word)
					surnames[word] = M
					surname_found = i
					break
			//forenames
			for(var/i=1, i<surname_found, i++)
				var/word = ckey(L[i])
				if(word)
					forenames[word] = M
			//ckeys
			ckeys[M.ckey] = M

	msg = ""
	var/list/mobs_found = list()
	for(var/original_word in msglist)
		var/word = ckey(original_word)
		if(word)
			if(!(word in adminhelp_ignored_words))
				var/mob/found = ckeys[word]
				if(!found)
					found = surnames[word]
					if(!found)
						found = forenames[word]
				if(found)
					if(!(found in mobs_found))
						mobs_found += found
						var/is_antag = 0
						if(found.mind && found.mind.special_role)
							is_antag = 1
						founds += "Name: [found.name]([found.real_name]) Key: [found.key] Ckey: [found.ckey] [is_antag ? "(Antag)" : null] "
						msg += "[original_word]<font size='1' color='[is_antag ? "red" : "black"]'>(<A HREF='?_src_=holder;[HrefToken(TRUE)];adminmoreinfo=[REF(found)]'>?</A>|<A HREF='?_src_=holder;[HrefToken(TRUE)];adminplayerobservefollow=[REF(found)]'>F</A>)</font> "
						continue
		msg += "[original_word] "
	if(irc)
		if(founds == "")
			return "Search Failed"
		else
			return founds

	return msg
