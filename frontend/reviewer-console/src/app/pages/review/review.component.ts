import { NgFor, NgIf } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { DecisioningService } from '../../services/decisioning.service';
import { DocumentRecord, DocumentsService } from '../../services/documents.service';

@Component({
  selector: 'app-review',
  standalone: true,
  imports: [NgFor, NgIf, FormsModule],
  template: `
    <div class="page">
      <h1>Review application</h1>

      <h3>Documents</h3>
      <ul>
        <li *ngFor="let doc of documents">
          {{ doc.type }} — {{ doc.status }}
          <button (click)="openDocument(doc.id)">View</button>
        </li>
      </ul>

      <h3>Decision</h3>
      <label>Reason<textarea [(ngModel)]="reason"></textarea></label>
      <button class="approve" (click)="decide('Approved')" [disabled]="deciding">Approve</button>
      <button class="reject" (click)="decide('Rejected')" [disabled]="deciding">Reject</button>
    </div>
  `,
})
export class ReviewComponent implements OnInit {
  applicationId = '';
  documents: DocumentRecord[] = [];
  reason = '';
  deciding = false;

  // In production this comes from the reviewer's Cognito-authenticated identity, not a
  // hardcoded value — this skeleton keeps auth wiring out of scope (see docs/architecture.md §8).
  private readonly reviewerId = '00000000-0000-0000-0000-000000000001';

  constructor(
    private readonly route: ActivatedRoute,
    private readonly router: Router,
    private readonly decisioning: DecisioningService,
    private readonly documentsService: DocumentsService,
  ) {}

  ngOnInit(): void {
    this.applicationId = this.route.snapshot.paramMap.get('id') ?? '';
    this.documentsService.getDocumentsForApplication(this.applicationId).subscribe((docs) => (this.documents = docs));
  }

  openDocument(documentId: string): void {
    this.documentsService.getDownloadUrl(documentId).subscribe((res) => window.open(res.downloadUrl, '_blank'));
  }

  decide(outcome: 'Approved' | 'Rejected'): void {
    this.deciding = true;
    this.decisioning.decide(this.applicationId, this.reviewerId, outcome, this.reason).subscribe({
      next: () => this.router.navigate(['/queue']),
      error: (err) => {
        this.deciding = false;
        console.error(err);
      },
    });
  }
}
