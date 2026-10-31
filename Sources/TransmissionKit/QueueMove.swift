/// Classic queue operations supported by Transmission 3.x and 4.x.
public enum QueueMove: String, CaseIterable, Sendable {
    case top = "queue-move-top"
    case up = "queue-move-up"
    case down = "queue-move-down"
    case bottom = "queue-move-bottom"
}
