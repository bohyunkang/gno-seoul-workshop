package memeland

import (
	"std"
	"strconv"
	"strings"
	"time"
	"sort"

	"gno.land/p/demo/avl"
	"gno.land/p/demo/seqid"
)

type Post struct {
	ID            string
	Data          string
	Author        std.Address
	Timestamp     time.Time
	UpvoteTracker *avl.Tree // address > struct{}{}
}

type Memeland struct {
	Posts       []*Post
	MemeCounter seqid.ID
}

// NewMemeland returns a pointer to a new Memeland object
// Initializes all the subfields
func NewMemeland() *Memeland {
	return &Memeland{
		Posts:   make([]*Post, 0),
	}
}

// PostMeme - Adds a new post at timestamp, with data
// Panics in case data is empty or timestamp is invalid
// Returns the ID of the created Post
func (m *Memeland) PostMeme(data string, timestamp int64) string {
	if data == "" {
		panic("data is empty")
	}
	if timestamp <= 0 {
		panic("timestamp is invalid")
	}

	id := m.MemeCounter.Next().String()

	newPost := &Post{
		ID:            id,
		Data:          data,
		Author:        std.PrevRealm().Addr(),
		Timestamp:     time.Unix(timestamp, 0),
		UpvoteTracker: avl.NewTree(),
	}

	m.Posts = append(m.Posts, newPost)

	return id
}


// Upvote increases the upvote count of a specific Post
// Panics if specified ID doesn't exist, or the user has already upvoted
func (m *Memeland) Upvote(id string) string {
	post := m.getPost(id)

	if post == nil {
		panic("specified ID doesn't exist")
	}

	userAddr := std.PrevRealm().Addr().String()

	if post.UpvoteTracker.Has(userAddr) {
		panic("user has already upvoted this post")
	}

	post.UpvoteTracker.Set(userAddr, struct{}{})

	return "successful"
}


// GetPostsInRange returns a JSON object containing marshalled Posts in a specific timestamp range
// Timestamps are given as Unix seconds
// Supports pagination
// sortBy can be "UPVOTES" (most upvotes-first), or "DATE_CREATED" (newest-first)
// Panics if page < 1, pageSize < 1, or pageSize > 10
// Returns empty JSON object if there are no posts in the specified range.
func (m *Memeland) GetPostsInRange(startTimestamp, endTimestamp int64, page, pageSize int, sortBy string) string {
	if len(m.Posts) == 0 {
		return "[]"
	}

	if page < 1 || pageSize < 1 || pageSize > 10 {
		panic("invalid pagination parameters")
	}

	// Filter posts by the given timestamp range
	var filteredPosts []*Post

	for _, post := range m.Posts {
		ts := post.Timestamp.Unix()
		if ts >= startTimestamp && ts <= endTimestamp {
		filteredPosts = append(filteredPosts, post)
		}
	}

	// Sort the filtered posts based on the sortBy parameter
	switch sortBy {
		// Sort by upvote descending
	case "UPVOTES":
		dateSorter := PostSorter{
			Posts: filteredPosts,
			LessF: func(i, j int) bool {
				return filteredPosts[i].UpvoteTracker.Size() > filteredPosts[j].UpvoteTracker.Size()
			},
		}
		sort.Sort(dateSorter)
	default:
		// Sort by timestamp, beginning with newest
		dateSorter := PostSorter{
			Posts: filteredPosts,
			LessF: func(i, j int) bool {
				return filteredPosts[i].Timestamp.After(filteredPosts[j].Timestamp)
			},
		}
		sort.Sort(dateSorter)
	}

	// Calculate the total number of pages
	totalPosts := len(filteredPosts)
	totalPages := totalPosts / pageSize

	if totalPosts%pageSize != 0 {
		totalPages++ // Account for the last page that might not be full
	}

	// Validate the requested page number
	if page > totalPages {
		return "[]" // Return an empty JSON array if the requested page exceeds the total pages
	}

	// Apply pagination to select a subset of filtered and sorted posts
	startIndex := (page - 1) * pageSize
	endIndex := startIndex + pageSize

	if endIndex > len(filteredPosts) {
		endIndex = len(filteredPosts) // Adjust the end index if it exceeds the array bounds
	}

	// Select the posts for the current page
	paginatedPosts := filteredPosts[startIndex:endIndex]

	// Convert the paginated posts to a JSON string and return
	return PostsToJSONString(paginatedPosts)
}

// getPost gets a post by ID
func (m *Memeland) getPost(id string) *Post {
	for _, post := range m.Posts {
		if post.ID == id {
			return post
		}
	}
	return nil
}

// PostsToJSONString converts a slice of Post structs into a JSON string
func PostsToJSONString(posts []*Post) string {
	var sb strings.Builder
	sb.WriteString("[")

	for i, post := range posts {
		if i > 0 {
			sb.WriteString(",")
		}

		sb.WriteString(PostToJSONString(post))
	}
	sb.WriteString("]")

	return sb.String()
}

// PostToJSONString returns a Post formatted as a JSON string
// Note: Gno currently does not support reflection, which is why JSON marshalling is unavailable
func PostToJSONString(post *Post) string {
	var sb strings.Builder

	sb.WriteString("{")
	sb.WriteString(`"id":"` + post.ID + `",`)
	sb.WriteString(`"data":"` + escapeString(post.Data) + `",`)
	sb.WriteString(`"author":"` + escapeString(post.Author.String()) + `",`)
	sb.WriteString(`"timestamp":"` + strconv.Itoa(int(post.Timestamp.Unix())) + `",`)
	sb.WriteString(`"upvotes":` + strconv.Itoa(post.UpvoteTracker.Size()))
	sb.WriteString("}")

	return sb.String()
}

// escapeString escapes quotes in a string for JSON compatibility.
func escapeString(s string) string {
	return strings.ReplaceAll(s, `"`, `\"`)
}

// PostSorter is a flexible sorter for the *Post slice
type PostSorter struct {
	Posts []*Post
	LessF func(i, j int) bool
}

func (p PostSorter) Len() int {
	return len(p.Posts)
}

func (p PostSorter) Swap(i, j int) {
	p.Posts[i], p.Posts[j] = p.Posts[j], p.Posts[i]
}

func (p PostSorter) Less(i, j int) bool {
	return p.LessF(i, j)
}
