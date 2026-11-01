# Momentary updates: Free Voice Convert

Every request, word for word, saved and pushed before any code.

## 1.11.2026, hub session: the first request

> Please, we need to build an application. We are also going to make a web page called Voice Convert. We call it Free
> Voice Convert. During the installation process, it downloads all the models. We did the research through the Elevate
> Media projects.
>
> Make a Windows application and a macOS Swift application. Of course, also a GitHub repository, a workflow to compile
> the apps on GitHub, and a workflow to build the website through GitHub.
>
> I am going to put in the secrets for pushing the site to Cloudflare. You just need to open that page in Chrome and open
> the setting for the variable you need to enter, like last time, and I will paste the numbers.
>
> First, build Free Voice Convert with the best models you already chose when we were trying them yesterday. The user
> interface is very simple: a source voice button and a file picker.
>
> Let's call the application Free Voice Convert Equalizer. Its purpose is exactly to make AI videos sound good, so it does
> automatically everything we are doing in DaVinci. You just pick the voice, and it outputs the voice so that all the
> clips sound the same, even if I am in different spaces and different environments. Through a cloned voice, it creates
> something similar to Ableton.
>
> This is what Adobe Podcast does. It has a profile of a certain sound and applies it to the whole recording. You can
> record with your phone and a tiny microphone, and it sounds like it was made in a studio. So the goal of this
> application is to take sound in and get equalized sound out, so all clips sound the same.
>
> The file picker is also the editor itself. It can stitch clips. You can put video files in, and it stitches everything
> and exports either one stitched file or individual converted files.
>
> The main goal is to have a sound profile. If you want, give me one voice and I will send it to Adobe Podcast. We will
> download the result, and you will make this acoustic quality profile from it, which we will apply to every sound. That
> way it sounds like it was recorded with a different microphone in a different environment.
>
> So the goal is basically to recreate the sound with the same voice in a different environment. We probably also need
> to transcribe, and then match the timings between the original and the new voice. Basically we recreate the voice from
> scratch, fitting the original source frame by frame. We are just converting one voice into another, which means
> copying the Adobe Podcast product for free.

## 1.11.2026, later: statistics, countdown, CPU/GPU/RAM meters, volume meters

> in the voice convert, I am missing the statistics when we are converting, where we are in time now and also the
> estimated time of finishing. For example, I have 5 files. You need to add all its length. Let's say it's 5 minutes.
> Then down there you have a counter: 5 minutes. Actually, you make a counter where we are in conversion: 5 minutes, and
> estimated time. You put the time of the clock, and also a timer that goes backwards. For example, if it needs 1 hour,
> then we just go backwards. You also need to show at what time it finishes also show GPU and CPU status: how much is
> under load in this computer or Windows computer? Imagine my meters in my application, TTT Mini, which is going
> horizontal. On one side is CPU, and on the other is GPU. They are just showing the current status. Also, two more:
> memory available (RAM) and GPU memory available. Also, volmeters. Make it happen
> (Marko, right after: "VU METERS ... THAT WAS MISSSPELET BY SPEACH TO TEXT": volmeters = VU meters.)

## 1.11.2026, later still: the style, one line, resume, no VU

> please make this app in my style. If you look at the TTT Mini repository, you will understand: first CPU, RAM, GPU,
> VRAM. The [VU] meter itself should be from [edge] to [edge], and then it should be hairline only

> all the times of estimation should be in only one line. Don't make converted time left finishes running everything
> in multiple lines. Make it everything in one line in one row

> feel free to extend the width of the application to accommodate all the numbers

> in this app, like in any app which downloads, you just need to always resume downloads. Even if the user closes the
> application and you open, it will continue where it left off so the user doesn't need to do it again

> I don't need a VU meter at the bottom. What is this? I don't understand. There is some VU meter appearing at the
> bottom of the screen Remove that.

> when I say a meter is not literally a meter, it's just an indication, remove that

> please don't calculate the final speed in x. Calculate it at frames per second. How many frames per second? From 25
> frames. This is converting. Or if they have video files, you can just take their own frame rate

> we have in the rule "How to export." I am missing: - Pipes - One by one - Pipe stitched - You need to give me pipes

> with times, it's not clear. There are so many numbers, and I don't know what each of them does. Same as CPU, RAM, GPU,
> VRAM. Make the same hairline under or everything, so we can see where we are. It's like a progress line. Also above
> each time, same as CPU, RAM, GPU. Put the labels of the time so we know what's going on there. Make a table layout

> I also need to see percentage converted. When I press "Stop to Convert," next to "Convert" it needs to say
> "Percentage." Instead of "Convert," it needs to say "Converted," let's say 50%. When I say "Convert" again, it
> continues

> please, as I'm resizing the user interface, all these status text converted time left [are] free. It's also enlarging
> [i.e. the status text should grow with the window]

> in this app, everything is hairlined. Under Converted, this progress bar should also be hairlined

> please, when I'm resizing the user interface, my top row, "Free Voice Converter of Top V4X," is being removed from
> the top of the program. I want this thing to be glued to the top. It doesn't fall apart. Actually, I want this: when
> I'm resizing the app, everything is becoming bigger, but at the same time, the area where my files are is not
> enlarging the font size. They are the same. Usually, when I'm resizing things, I want to see more of that box, more
> of my files

> to make things clear, you need to also build. Now it's 3, converted 8%. That must have a pause button and a stop button
> but actually, one button is enough: only Stop. Then when you press Stop, Stop becomes Resume

> in this app, please build a horizontal line before and after every step. You can look at my app now. It's on screen,
> called Download Aggregator. Add horizontal lines so we can clearly and visually see the distinction between elements
> of this user interface

> if not already, this app should remember its last position and on which screen it was positioned

> now, please, when there is a converted time left, it ends at running speed. The font size would be the same as CPU RAM
> free, GPU RAM free, same. Now, convert these tiny numbers. I even cannot read. Total nonsense.

> please, with the pipe next to add files, add also new task button so user can reset the user interface to be clear and
> then add files. Without that, he's just adding more and more files

## 1.11.2026: the page order (banner, introduction, lifestyle, technical, donation)

> "the page is perfect. Let's do it all pages" (Marko, 1.11.2026, about mantramiditools.pages.dev)

1. Every public app page in the order of MANTRA_MANIFEST modules/app-page-order.md: the banner (the app at work, name and one line on it), a short introduction with the download button and the version line, the lifestyle picture, the technical part, the donation bowl.

**Status:** done 1.11.2026 (site/public/index.html, published by .github/workflows/site.yml): banner img/hero.jpg with the icon and the name on it, the introduction with both downloads and the version line (__VERSION__ kept, filled at deploy), the lifestyle picture img/lifestyle.jpg, the technical part (requirements, the five steps, how to use, nothing lost, installing), the bowl.

## 1.11.2026: download links that follow every new version by themselves

> "yes, fix download links so every website gets each new version by itself" (Marko, 1.11.2026)

**Status:** done 1.11.2026 (MANTRA_MANIFEST modules/download-always-latest.md): the buttons link download/FreeVoiceConvert.dmg and download/FreeVoiceConvert-Setup.exe; .github/workflows/site.yml fills them from the newest release after every "Build apps" and writes its tag as the version; site/public/_redirects sends the old versioned names 301 to them. Verified live: both 200, 381900 and 2134572 bytes = release v4, page shows version 4.

## 1.11.2026: My studio setup, a link above the bowl

> "Just above the Tibetan bowl for donation, you can just make one link, and then it will open the page with all lifestyle images and images of these products which I'm using in my development studio ... For this link, you can say "My studio setup." ... It is opening a new page, which is going to call studio setup mantra.pages.dev" (Marko, 1.11.2026)

1. One centred link "My studio setup" right above the donation bowl, opening https://studiosetupmantra.pages.dev in a new tab, with the line "The gear these apps are made with · affiliate links on Amazon.de".

**Status:** committed 1.11.2026, NOT pushed or deployed: waiting until Marko registers studiosetupmantra.pages.dev in Amazon PartnerNet and the studio page is live.
