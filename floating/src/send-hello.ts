import { Spectrum } from "spectrum-ts";
import { imessage } from "spectrum-ts/providers/imessage";

const recipient = process.env.PHOTON_RECIPIENT ?? process.env.PHOTON_ALLOWED_SENDER;

if (!recipient) {
  throw new Error("Set PHOTON_RECIPIENT to your phone number in E.164 format.");
}

const spectrum = await Spectrum({
  projectId: process.env.PROJECT_ID!,
  projectSecret: process.env.PROJECT_SECRET!,
  providers: [imessage.config()],
});

try {
  const provider = imessage(spectrum);
  const user = await provider.user(recipient);
  const space = await provider.space.create(user);

  await space.send("hello world");
  console.log(`Sent hello world to ${recipient}.`);
} finally {
  await spectrum.stop();
}
