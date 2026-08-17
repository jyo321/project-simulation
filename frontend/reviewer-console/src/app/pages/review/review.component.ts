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
      <div class="page-header">
        <h1>Review application</h1>
        <p class="page-subtitle">Check the submitted documents, then approve or reject with a reason.</p>
      </div>

      <h3>Documents</h3>
      <ul class="doc-list" *ngIf="documents.length">
        <li *ngFor="let doc of documents">
          <span class="upload-item-name">{{ doc.type }} <span class="status-badge">{{ doc.status }}</span></span>
          <button class="secondary" (click)="openDocument(doc.id)">View</button>
        </li>
      </ul>
      <p *ngIf="!documents.length" style="margin-top: 0">No documents uploaded yet.</p>

      <h3>Decision</h3>
      <label>Reason<textarea [(ngModel)]="reason" placeholder="Why are you approving or rejecting this application?"></textarea></label>
      <button class="approve" (click)="decide('Approved')" [disabled]="deciding">Approve</button>
      <button class="reject" (click)="decide('Rejected')" [disabled]="deciding" style="margin-left: 10px">Reject</button>
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
