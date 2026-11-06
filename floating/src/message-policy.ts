type MessageIdentity = {
  platform: string;
  direction: string;
  service?: string | undefined;
  sender?: { id: string } | undefined;
};

/** A single saved Cognito session must never be exposed to other senders or groups. */
export function mayHandleMessage(message: MessageIdentity, spaceType: string, allowedSender: string): boolean {
  return allowedSender.trim().length > 0 &&
    message.platform === "imessage" &&
    message.direction === "inbound" &&
    message.service === "iMessage" &&
    spaceType === "dm" &&
    message.sender?.id === allowedSender;
}
