# aichat.allow.folder.offer.jq - the line that offers Allow a Folder... after a tool call was
# refused a folder, as the element _allow_folder_offer_show (aichat.allow.folder.library.sh)
# puts under the chat.
#
#     /usr/bin/jq -c -n --argjson row ID --argjson path ID --argjson button ID --argjson dismiss ID \
#         --arg help FOLDER -f aichat.allow.folder.offer.jq
#
# The four ids are the row's, the folder text's and the two buttons'. FOLDER is the folder's full
# path, shown as the text's tooltip; the text itself is set afterwards, as the element's value,
# which is what the chooser of aichat.chat.allow.folder.choose opens at.

{type: "HStack", id: $row,
  properties: {spacing: 8, padding: {top: 6, leading: 14, bottom: 6, trailing: 14}, frame: {maxWidth: "infinity", alignment: "leading"}},
  children: [
    {type: "Image", properties: {systemName: "folder.badge.questionmark", foregroundStyle: "secondary"}},
    {type: "Text", properties: {text: "A tool was refused", foregroundStyle: "secondary"}},
    {type: "Text", id: $path, properties: {text: "", help: $help}},
    {type: "Button", id: $button, properties: {title: "Allow a Folder...", buttonStyle: "bordered", controlSize: "small", help: "Choose the folder to allow for this window. The chooser opens at this one.", actionID: "aichat.chat.allow.folder.offered"}},
    {type: "Button", id: $dismiss, properties: {title: "Dismiss", buttonStyle: "borderless", controlSize: "small", help: "Do not offer this folder again in this window", actionID: "aichat.chat.allow.folder.dismiss"}},
    {type: "Spacer"}
  ]}
